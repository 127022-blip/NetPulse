import Foundation

/// 内存监控服务 - 获取内存使用率（按需采样，无独立高频 Timer）
final class MemoryMonitorService {
    static let shared = MemoryMonitorService()

    private var currentMemoryUsage: Double = 0.0
    private var lastSampleAt: Date?
    private let minSampleInterval: TimeInterval = 1.0

    private init() {}

    private func sampleMemoryUsageIfNeeded() {
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
        let usedMemory = activeMemory + wiredMemory

        currentMemoryUsage = max(0.0, min(100.0, Double(usedMemory) / Double(totalMemory) * 100.0))
    }

    func getMemoryUsage() -> Double {
        sampleMemoryUsageIfNeeded()
        return currentMemoryUsage
    }

    func getFormattedMemoryUsage() -> String {
        String(format: "%.0f%%", getMemoryUsage())
    }

    func getUsedMemoryGB() -> Double {
        sampleMemoryUsageIfNeeded()
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0.0 }

        let pageSize = Double(vm_kernel_page_size)
        let activeMemory = Double(stats.active_count) * pageSize
        let wiredMemory = Double(stats.wire_count) * pageSize
        return (activeMemory + wiredMemory) / (1024 * 1024 * 1024)
    }

    func getTotalMemoryGB() -> Double {
        Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }
}
