import Foundation

/// 内存监控服务：串行锁 + 不可变快照
/// 口径说明：使用率 ≈ (active + wired + compressor) / physicalMemory × 100
/// （接近活动监视器「已用内存」思路；不含 inactive/free，色阶仍沿用同一百分比）
final class MemoryMonitorService {
    static let shared = MemoryMonitorService()

    struct Snapshot: Equatable {
        let percent: Double
        let formatted: String
        let usedGB: Double
        let totalGB: Double
    }

    private let lock = NSLock()
    private var currentMemoryUsage: Double = 0.0
    private var currentUsedGB: Double = 0.0
    private var lastSampleAt: Date?
    private let minSampleInterval: TimeInterval = 1.0

    private init() {}

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        sampleMemoryUsageIfNeededLocked()
        let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        let p = currentMemoryUsage
        return Snapshot(
            percent: p,
            formatted: String(format: "%.0f%%", p),
            usedGB: currentUsedGB,
            totalGB: totalGB
        )
    }

    func getMemoryUsage() -> Double { snapshot().percent }
    func getFormattedMemoryUsage() -> String { snapshot().formatted }
    func getUsedMemoryGB() -> Double { snapshot().usedGB }
    func getTotalMemoryGB() -> Double { snapshot().totalGB }

    private func sampleMemoryUsageIfNeededLocked() {
        if let last = lastSampleAt, Date().timeIntervalSince(last) < minSampleInterval {
            return
        }
        lastSampleAt = Date()

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let activeMemory = UInt64(stats.active_count) * pageSize
        let wiredMemory = UInt64(stats.wire_count) * pageSize
        // compressor_page_count：压缩内存页
        let compressedMemory = UInt64(stats.compressor_page_count) * pageSize
        let usedMemory = activeMemory + wiredMemory + compressedMemory

        currentUsedGB = Double(usedMemory) / (1024 * 1024 * 1024)
        currentMemoryUsage = max(0.0, min(100.0, Double(usedMemory) / Double(totalMemory) * 100.0))
    }
}
