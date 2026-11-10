import Foundation

/// CPU 温度监视器：AppleSMC（命令 9 再命令 5，按类型解码）优先，失败时回退 IOKit HID。
/// 协议、键表、解码与 HID 排除规则与已核验的 BarTemp 1.0.0 一致。
final class CPUTemperatureMonitor {
    static let shared = CPUTemperatureMonitor()

    private let smc = SMCTemperatureReader()
    private let hid = HIDTemperatureReader()
    private let chip = ChipFamily.detect()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.netpulse.cpu-temperature", qos: .utility)

    private(set) var latest = TemperatureReading.unavailable(detail: "尚未采样")
    var onUpdate: ((TemperatureReading) -> Void)?

    var chipDescription: String { chip.displayName }

    func start(intervalSeconds: Double = 1.5) {
        stop()
        sampleOnce()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.sampleOnce()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        smc.close()
    }

    func probeNow() -> TemperatureReading {
        readNow()
    }

    func diagnose() -> String {
        let smcReader = smc
        let keys = smcReader.diagnosePreferredKeys(chip.preferredSMCKeys)
        let hidSamples = hid.readAllCPUSamples()
        var lines: [String] = []
        lines.append("chip=\(chip.displayName)")
        lines.append("smc_struct_size=\(SMCBridgeStructSize())")
        lines.append("smc_open=\(smcReader.open())")
        if keys.isEmpty {
            lines.append("smc_keys=none")
        } else {
            for row in keys {
                lines.append(String(format: "smc %@ type=%@ value=%.2fC", row.0, row.2, row.1))
            }
        }
        if hidSamples.isEmpty {
            lines.append("hid_sensors=none")
        } else {
            for sample in hidSamples {
                lines.append(String(format: "hid %@ value=%.2fC", sample.name, sample.celsius))
            }
        }
        return lines.joined(separator: "\n")
    }

    private func sampleOnce() {
        let reading = readNow()
        latest = reading
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onUpdate?(reading)
        }
    }

    private func readNow() -> TemperatureReading {
        let now = Date()

        if let smcSample = smc.readBestCPUTemperature(preferredKeys: chip.preferredSMCKeys) {
            return TemperatureReading(
                celsius: smcSample.celsius,
                sourceKind: .smc,
                sourceDetail: "键 \(smcSample.key)（\(smcSample.type)）· \(chip.displayName)",
                sampledAt: now
            )
        }

        if let hidSample = hid.readBestCPUTemperature() {
            return TemperatureReading(
                celsius: hidSample.celsius,
                sourceKind: .hid,
                sourceDetail: "\(hidSample.name) · \(chip.displayName)",
                sampledAt: now
            )
        }

        return .unavailable(detail: "AppleSMC 与 HID 均未得到可信 CPU 温度 · \(chip.displayName)", at: now)
    }
}
