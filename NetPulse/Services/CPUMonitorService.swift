import Foundation

/// CPU 监控服务 - 获取 CPU 使用率（按需采样，无独立高频 Timer）
final class CPUMonitorService {
    static let shared = CPUMonitorService()

    private var currentCPUUsage: Double = 0.0
    private var prevTotalTicks: UInt64 = 0
    private var prevIdleTicks: UInt64 = 0
    private var lastSampleAt: Date?
    private let minSampleInterval: TimeInterval = 1.0

    private init() {}

    /// 采样 CPU 使用率（带最短间隔，避免过频）
    private func sampleCPUUsageIfNeeded() {
        if let last = lastSampleAt, Date().timeIntervalSince(last) < minSampleInterval {
            return
        }
        lastSampleAt = Date()

        var cpuLoadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        let userTicks = UInt64(cpuLoadInfo.cpu_ticks.0)
        let systemTicks = UInt64(cpuLoadInfo.cpu_ticks.1)
        let idleTicks = UInt64(cpuLoadInfo.cpu_ticks.2)
        let niceTicks = UInt64(cpuLoadInfo.cpu_ticks.3)

        let totalTicks = userTicks + systemTicks + idleTicks + niceTicks

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

        guard totalDelta > 0 else { return }

        let cpuUsage = Double(totalDelta - idleDelta) / Double(totalDelta) * 100.0
        currentCPUUsage = max(0.0, min(100.0, cpuUsage))
    }

    func getCPUUsage() -> Double {
        sampleCPUUsageIfNeeded()
        return currentCPUUsage
    }

    func getFormattedCPUUsage() -> String {
        String(format: "%.0f%%", getCPUUsage())
    }
}
