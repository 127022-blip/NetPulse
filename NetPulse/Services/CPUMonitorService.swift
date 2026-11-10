import Foundation

/// CPU 监控服务：串行锁 + 不可变快照，可在后台队列采样
final class CPUMonitorService {
    static let shared = CPUMonitorService()

    struct Snapshot: Equatable {
        let percent: Double
        let formatted: String
    }

    private let lock = NSLock()
    private var currentCPUUsage: Double = 0.0
    private var prevTotalTicks: UInt64 = 0
    private var prevIdleTicks: UInt64 = 0
    private var lastSampleAt: Date?
    private let minSampleInterval: TimeInterval = 1.0

    private init() {}

    /// 采样并返回不可变快照（线程安全）
    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        sampleCPUUsageIfNeededLocked()
        let p = currentCPUUsage
        return Snapshot(percent: p, formatted: String(format: "%.0f%%", p))
    }

    func getCPUUsage() -> Double { snapshot().percent }
    func getFormattedCPUUsage() -> String { snapshot().formatted }

    private func sampleCPUUsageIfNeededLocked() {
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
}
