import Foundation

/// CPU 监控服务 - 获取 CPU 使用率
final class CPUMonitorService {
    static let shared = CPUMonitorService()

    // 定时采样
    private var sampleTimer: Timer?
    
    // 当前采样的 CPU 使用率
    private var currentCPUUsage: Double = 0.0
    
    // 上一次采样
    private var prevTotalTicks: UInt64 = 0
    private var prevIdleTicks: UInt64 = 0

    private init() {
        startSampling()
    }
    
    deinit {
        sampleTimer?.invalidate()
    }
    
    /// 启动定时采样（每秒一次）
    private func startSampling() {
        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sampleCPUUsage()
        }
        RunLoop.main.add(sampleTimer!, forMode: .common)
    }
    
    /// 采样 CPU 使用率
    private func sampleCPUUsage() {
        var cpuLoadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return
        }

        // 获取 ticks
        let userTicks = UInt64(cpuLoadInfo.cpu_ticks.0)
        let systemTicks = UInt64(cpuLoadInfo.cpu_ticks.1)
        let idleTicks = UInt64(cpuLoadInfo.cpu_ticks.2)
        let niceTicks = UInt64(cpuLoadInfo.cpu_ticks.3)

        let totalTicks = userTicks + systemTicks + idleTicks + niceTicks

        // 首次采样
        if prevTotalTicks == 0 {
            prevTotalTicks = totalTicks
            prevIdleTicks = idleTicks
            currentCPUUsage = 0.0
            return
        }

        let totalDelta = totalTicks - prevTotalTicks
        let idleDelta = idleTicks - prevIdleTicks

        prevTotalTicks = totalTicks
        prevIdleTicks = idleTicks

        guard totalDelta > 0 else {
            return
        }

        // CPU使用率 = (总 ticks - 空闲 ticks) / 总 ticks
        let cpuUsage = Double(totalDelta - idleDelta) / Double(totalDelta) * 100.0
        currentCPUUsage = max(0.0, min(100.0, cpuUsage))
    }

    /// 获取 CPU 使用率 (0.0 - 100.0) - 从缓存返回
    func getCPUUsage() -> Double {
        return currentCPUUsage
    }

    /// 获取格式化 CPU 使用率字符串
    func getFormattedCPUUsage() -> String {
        return String(format: "%.0f%%", currentCPUUsage)
    }
}
