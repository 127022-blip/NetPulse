import Foundation
import IOKit

/// CPU 温度监控服务（按需读取，无消费者时不空转采样）
final class CPUTemperatureService {
    static let shared = CPUTemperatureService()

    private var currentTemperature: Double = 0.0
    private var smcConnection: io_connect_t = 0
    private var lastSuccessfulRead: Date?
    private let cacheValidDuration: TimeInterval = 30.0
    private var smcOpened = false

    private init() {
        // 不在 init 中开 SMC / 启 Timer，避免无消费者空转
    }

    deinit {
        closeSMC()
    }

    private func ensureSMC() {
        guard !smcOpened else { return }
        smcOpened = true
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service != 0 {
            let result = IOServiceOpen(service, mach_task_self_, 0, &smcConnection)
            IOObjectRelease(service)
            if result != kIOReturnSuccess {
                print("CPUTemperatureService: Failed to open SMC: \(result)")
                smcConnection = 0
            }
        } else {
            print("CPUTemperatureService: AppleSMC service not found")
        }
    }

    private func closeSMC() {
        if smcConnection != 0 {
            IOServiceClose(smcConnection)
            smcConnection = 0
        }
    }

    private func readCPUTemperature() -> Double {
        ensureSMC()
        guard smcConnection != 0 else { return 0.0 }

        let keys = ["TC0P", "TC0D", "TC0H", "TC0C", "TC0E", "TC0F", "TC0G"]
        for key in keys {
            if let temp = readSMCKey(key) {
                return temp
            }
        }
        return 0.0
    }

    private func readSMCKey(_ key: String) -> Double? {
        guard smcConnection != 0 else { return nil }

        struct SMCKeyData {
            var key: UInt32 = 0
            var vers: UInt8 = 0
            var pLimitData: UInt8 = 0
            var keyInfo: UInt8 = 0
            var result: UInt8 = 0
            var status: UInt8 = 0
            var data8: UInt8 = 0
            var data32: UInt32 = 0
            var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
                (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        }

        let keyBytes = Array(key.utf8)
        guard keyBytes.count >= 4 else { return nil }

        let keyCode = UInt32(keyBytes[0]) << 24 |
                      UInt32(keyBytes[1]) << 16 |
                      UInt32(keyBytes[2]) << 8 |
                      UInt32(keyBytes[3])

        var inputData = SMCKeyData()
        var outputData = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.size

        inputData.key = keyCode
        inputData.data8 = 5 // SMC_CMD_READ_KEYINFO

        var result = IOConnectCallStructMethod(
            smcConnection,
            2,
            &inputData,
            MemoryLayout<SMCKeyData>.size,
            &outputData,
            &outputSize
        )
        guard result == KERN_SUCCESS else { return nil }

        let dataSize = Int(outputData.data8)
        guard dataSize > 0 && dataSize <= 32 else { return nil }

        inputData.data8 = 6 // SMC_CMD_READ_BYTES
        inputData.data32 = UInt32(dataSize)

        outputSize = MemoryLayout<SMCKeyData>.size
        result = IOConnectCallStructMethod(
            smcConnection,
            2,
            &inputData,
            MemoryLayout<SMCKeyData>.size,
            &outputData,
            &outputSize
        )
        guard result == KERN_SUCCESS else { return nil }

        let bytes = withUnsafeBytes(of: outputData.bytes) { Array($0) }
        if bytes[0] > 20 && bytes[0] < 120 {
            return Double(bytes[0])
        }
        if dataSize >= 4 {
            let floatValue = withUnsafeBytes(of: outputData.bytes.0) { $0.load(as: Float32.self) }
            if floatValue > 20 && floatValue < 120 {
                return Double(floatValue)
            }
        }
        return nil
    }

    /// 按需获取 CPU 温度（带缓存；无调用则不采样）
    func getCPUTemperature() -> Double {
        if let last = lastSuccessfulRead,
           Date().timeIntervalSince(last) < cacheValidDuration,
           currentTemperature > 0 {
            return currentTemperature
        }
        let temp = readCPUTemperature()
        if temp > 0 {
            currentTemperature = temp
            lastSuccessfulRead = Date()
        }
        return currentTemperature
    }

    func getFormattedCPUTemperature() -> String {
        let t = getCPUTemperature()
        if t > 0 {
            return String(format: "%.0f°", t)
        }
        return "--°"
    }
}
