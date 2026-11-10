import Foundation
import Darwin

/// IOKit HID temperature sensors (the same name patterns Stats publishes).
/// Uses dlsym so the private EventSystemClient symbols do not have to appear in SDK headers.
/// Battery / gas-gauge sensors are always ignored.
final class HIDTemperatureReader {
    private let cpuNameHints = [
        "pACC MTR Temp Sensor",
        "eACC MTR Temp Sensor",
        "sACC MTR Temp Sensor",
        "CPU MTR Temp Sensor"
    ]

    func readBestCPUTemperature() -> (celsius: Double, name: String)? {
        let samples = readAllCPUSamples()
        return samples.max(by: { $0.celsius < $1.celsius })
    }

    func readAllCPUSamples() -> [(celsius: Double, name: String)] {
        guard let client = HIDNative.createSimpleClient() else { return [] }
        defer { /* client is process-lifetime; Apple clients are typically not CFReleased here */ }
        guard let services = HIDNative.copyServices(client) else { return [] }

        var samples: [(celsius: Double, name: String)] = []
        for service in services {
            let name = HIDNative.copyString(service, "Product")
                ?? HIDNative.copyString(service, "IOHIDEventServiceSensorName")
                ?? HIDNative.copyString(service, "Product")
            guard let productName = name, isCPUSensorName(productName) else { continue }
            guard let value = HIDNative.temperatureEvent(service) else { continue }
            var celsius = value
            // Some HID reports are Kelvin.
            if celsius > 200, celsius < 400 {
                celsius -= 273.15
            }
            guard SMCValueDecoder.isPlausibleCPUTemperature(celsius) else { continue }
            samples.append((celsius, productName))
        }
        return samples
    }

    private func isCPUSensorName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("battery") || lower.contains("gas gauge") || lower.contains("nand") {
            return false
        }
        if lower.contains("gpu") { return false }
        return cpuNameHints.contains { name.contains($0) }
    }
}

private enum HIDNative {
    private static let kIOHIDEventTypeTemperature = 15
    private static func fieldBase(_ type: Int) -> Int32 { Int32(type << 16) }

    private static let iokit: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    }()

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let iokit, let raw = dlsym(iokit, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }

    static func createSimpleClient() -> UnsafeMutableRawPointer? {
        typealias Fn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
        if let fn = symbol("IOHIDEventSystemClientCreateSimpleClient", as: Fn.self) {
            return fn(kCFAllocatorDefault)
        }
        typealias Fn2 = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
        if let fn = symbol("IOHIDEventSystemClientCreate", as: Fn2.self) {
            return fn(kCFAllocatorDefault)
        }
        return nil
    }

    static func copyServices(_ client: UnsafeMutableRawPointer) -> [UnsafeMutableRawPointer]? {
        typealias Fn = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
        guard let fn = symbol("IOHIDEventSystemClientCopyServices", as: Fn.self) else { return nil }
        guard let array = fn(client)?.takeRetainedValue() as? [AnyObject] else { return nil }
        return array.map { unsafeBitCast($0, to: UnsafeMutableRawPointer.self) }
    }

    static func copyString(_ service: UnsafeMutableRawPointer, _ key: String) -> String? {
        typealias Fn = @convention(c) (UnsafeMutableRawPointer, CFString) -> Unmanaged<AnyObject>?
        guard let fn = symbol("IOHIDServiceClientCopyProperty", as: Fn.self) else { return nil }
        return fn(service, key as CFString)?.takeRetainedValue() as? String
    }

    static func temperatureEvent(_ service: UnsafeMutableRawPointer) -> Double? {
        typealias CopyEvent = @convention(c) (UnsafeMutableRawPointer, Int64, Int64, Int32) -> UnsafeMutableRawPointer?
        typealias GetFloat = @convention(c) (UnsafeMutableRawPointer, Int32) -> Double
        guard let copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEvent.self),
              let getFloat = symbol("IOHIDEventGetFloatValue", as: GetFloat.self) else {
            return nil
        }
        guard let event = copyEvent(service, Int64(kIOHIDEventTypeTemperature), 0, 0) else {
            return nil
        }
        return getFloat(event, fieldBase(kIOHIDEventTypeTemperature))
    }
}
