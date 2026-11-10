import Foundation

/// Decodes SMC sensor bytes according to the published type fourcc.
enum SMCValueDecoder {
    static func temperatureCelsius(type: String, bytes: [UInt8], size: Int) -> Double? {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        guard size > 0, bytes.count >= size else { return nil }

        switch trimmed {
        case "sp78":
            guard size >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256.0
        case "sp87":
            guard size >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 128.0
        case "flt", "float":
            guard size >= 4 else { return nil }
            var bits: UInt32 = 0
            // Apple Silicon SMC floats are typically little-endian host order.
            bits |= UInt32(bytes[0])
            bits |= UInt32(bytes[1]) << 8
            bits |= UInt32(bytes[2]) << 16
            bits |= UInt32(bytes[3]) << 24
            let value = Float(bitPattern: bits)
            return value.isFinite ? Double(value) : nil
        case "ui8", "UI8":
            return Double(bytes[0])
        case "ui16":
            guard size >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "fp88":
            guard size >= 2 else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 256.0
        default:
            // Heuristic fallback only when type is unknown: try flt then sp78.
            if size >= 4 {
                var bits: UInt32 = 0
                bits |= UInt32(bytes[0])
                bits |= UInt32(bytes[1]) << 8
                bits |= UInt32(bytes[2]) << 16
                bits |= UInt32(bytes[3]) << 24
                let value = Float(bitPattern: bits)
                if value.isFinite, value > 5, value < 125 {
                    return Double(value)
                }
            }
            if size >= 2 {
                let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
                let c = Double(raw) / 256.0
                if c > 5, c < 125 { return c }
            }
            return nil
        }
    }

    static func isPlausibleCPUTemperature(_ celsius: Double) -> Bool {
        celsius.isFinite && celsius >= 10 && celsius <= 125
    }
}

final class SMCTemperatureReader {
    private(set) var isOpen = false
    private var workingKeys: [String] = []
    private var discoveredOnce = false

    deinit {
        close()
    }

    @discardableResult
    func open() -> Bool {
        if isOpen { return true }
        isOpen = SMCBridgeOpen()
        return isOpen
    }

    func close() {
        if isOpen {
            SMCBridgeClose()
            isOpen = false
        }
    }

    func readBestCPUTemperature(preferredKeys: [String]) -> (celsius: Double, key: String, type: String)? {
        guard open() else { return nil }

        if !discoveredOnce {
            discoveredOnce = true
            workingKeys = discoverWorkingKeys(preferredKeys: preferredKeys)
        }

        let keysToTry: [String]
        if workingKeys.isEmpty {
            keysToTry = preferredKeys
        } else {
            keysToTry = workingKeys
        }

        var samples: [(Double, String, String)] = []
        for key in keysToTry {
            if let sample = readTemperature(key: key) {
                samples.append(sample)
            }
        }

        // Prefer the hottest plausible CPU core reading — closer to "CPU 温度" UX.
        guard let best = samples.max(by: { $0.0 < $1.0 }) else {
            // One-shot rediscovery if cached keys went stale.
            workingKeys = discoverWorkingKeys(preferredKeys: preferredKeys)
            for key in workingKeys {
                if let sample = readTemperature(key: key) {
                    samples.append(sample)
                }
            }
            return samples.max(by: { $0.0 < $1.0 }).map { ($0.0, $0.1, $0.2) }
        }
        return (best.0, best.1, best.2)
    }

    private func discoverWorkingKeys(preferredKeys: [String]) -> [String] {
        var found: [String] = []
        for key in preferredKeys {
            if readTemperature(key: key) != nil {
                found.append(key)
            }
        }
        if !found.isEmpty { return found }

        // Scan all published keys whose name starts with T and looks CPU-ish.
        let count = Int(SMCBridgeKeyCount())
        guard count > 0, count < 4096 else { return found }
        for index in 0..<count {
            var name = [CChar](repeating: 0, count: 5)
            guard SMCBridgeKeyAtIndex(UInt32(index), &name) else { continue }
            let key = String(cString: name)
            guard key.count == 4 else { continue }
            let upper = key.uppercased()
            // Skip battery / ambient / NAND-ish keys that must not impersonate CPU.
            if upper.hasPrefix("TB") || upper.hasPrefix("TA") || upper.hasPrefix("TH0") { continue }
            if upper.hasPrefix("TP") || upper.hasPrefix("TE") || upper.hasPrefix("TF") || upper.hasPrefix("TC") {
                if readTemperature(key: key) != nil {
                    found.append(key)
                }
            }
        }
        return found
    }

    func diagnosePreferredKeys(_ keys: [String]) -> [(key: String, celsius: Double, type: String)] {
        guard open() else { return [] }
        var rows: [(key: String, celsius: Double, type: String)] = []
        for key in keys {
            if let sample = readTemperature(key: key) {
                rows.append((key: sample.1, celsius: sample.0, type: sample.2))
            }
        }
        return rows
    }

    private func readTemperature(key: String) -> (Double, String, String)? {
        var value = SMCBridgeValue()
        guard SMCBridgeReadKey(key, &value) else { return nil }
        let type = withUnsafePointer(to: value.dataType) {
            $0.withMemoryRebound(to: CChar.self, capacity: 5) { String(cString: $0) }
        }
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0) }
        guard let celsius = SMCValueDecoder.temperatureCelsius(type: type, bytes: bytes, size: Int(value.dataSize)),
              SMCValueDecoder.isPlausibleCPUTemperature(celsius) else {
            return nil
        }
        return (celsius, key, type.trimmingCharacters(in: .whitespaces))
    }
}
