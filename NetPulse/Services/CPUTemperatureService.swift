import Foundation
import IOKit

/// CPU 温度监控服务
final class CPUTemperatureService {
    static let shared = CPUTemperatureService()

    // 当前温度缓存
    private var currentTemperature: Double = 0.0
    
    // SMC 连接
    private var smcConnection: io_connect_t = 0
    
    // 定时采样
    private var sampleTimer: Timer?
    
    // 上次成功获取温度的时间
    private var lastSuccessfulRead: Date?
    
    // 缓存有效期（30秒）
    private let cacheValidDuration: TimeInterval = 30.0

    private init() {
        openSMC()
        startSampling()
        // 启动时立即获取一次温度
        fetchTemperatureOnce()
    }
    
    deinit {
        sampleTimer?.invalidate()
        closeSMC()
    }
    
    /// 打开 SMC 连接
    private func openSMC() {
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
    
    /// 关闭 SMC 连接
    private func closeSMC() {
        if smcConnection != 0 {
            IOServiceClose(smcConnection)
            smcConnection = 0
        }
    }
    
    /// 启动定时采样（每秒一次）
    private func startSampling() {
        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sampleTemperature()
        }
        RunLoop.main.add(sampleTimer!, forMode: .common)
    }
    
    /// 采样温度
    private func sampleTemperature() {
        // 如果有有效缓存，跳过
        if let lastRead = lastSuccessfulRead, 
           Date().timeIntervalSince(lastRead) < cacheValidDuration && currentTemperature > 0 {
            return
        }
        
        let temp = readCPUTemperature()
        if temp > 0 {
            currentTemperature = temp
            lastSuccessfulRead = Date()
        }
    }
    
    /// 获取温度
    private func fetchTemperatureOnce() {
        let temp = readCPUTemperature()
        if temp > 0 {
            currentTemperature = temp
            lastSuccessfulRead = Date()
        }
    }
    
    /// 读取 CPU 温度
    private func readCPUTemperature() -> Double {
        guard smcConnection != 0 else { return 0.0 }
        
        // 尝试多个温度键
        let keys = ["TC0P", "TC0D", "TC0H", "TC0C", "TC0E", "TC0F", "TC0G"]
        
        for key in keys {
            if let temp = readSMCKey(key) {
                return temp
            }
        }
        
        return 0.0
    }
    
    /// 读取单个 SMC 键
    private func readSMCKey(_ key: String) -> Double? {
        guard smcConnection != 0 else { return nil }
        
        // SMC 数据结构
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
        
        // 将字符串键转换为 UInt32
        let keyBytes = Array(key.utf8)
        guard keyBytes.count >= 4 else { return nil }
        
        let keyCode = UInt32(keyBytes[0]) << 24 | 
                      UInt32(keyBytes[1]) << 16 | 
                      UInt32(keyBytes[2]) << 8 | 
                      UInt32(keyBytes[3])
        
        var inputData = SMCKeyData()
        var outputData = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.size
        
        // 获取键信息
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
        
        // 读取数据
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
        
        // 解析温度 - 通常是第一个字节
        let bytes = withUnsafeBytes(of: outputData.bytes) { Array($0) }
        
        if bytes[0] > 20 && bytes[0] < 120 {
            return Double(bytes[0])
        }
        
        // 尝试浮点数
        if dataSize >= 4 {
            let floatValue = withUnsafeBytes(of: outputData.bytes.0) { $0.load(as: Float32.self) }
            if floatValue > 20 && floatValue < 120 {
                return Double(floatValue)
            }
        }
        
        return nil
    }

    /// 获取 CPU 温度
    func getCPUTemperature() -> Double {
        return currentTemperature
    }
    
    /// 获取格式化温度字符串
    func getFormattedCPUTemperature() -> String {
        if currentTemperature > 0 {
            return String(format: "%.0f°", currentTemperature)
        }
        return "--°"
    }
}
