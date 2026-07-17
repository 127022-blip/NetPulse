import Foundation

/// 内存监控服务 - 获取内存使用率
final class MemoryMonitorService {
    static let shared = MemoryMonitorService()

    // 定时采样
    private var sampleTimer: Timer?
    
    // 当前采样的内存使用率
    private var currentMemoryUsage: Double = 0.0

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
            self?.sampleMemoryUsage()
        }
        RunLoop.main.add(sampleTimer!, forMode: .common)
    }
    
    /// 采样内存使用率
    private func sampleMemoryUsage() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return
        }

        let pageSize = UInt64(vm_kernel_page_size)

        // 总物理内存
        let totalMemory = ProcessInfo.processInfo.physicalMemory

        // 已使用内存 = (active + wired down)
        let activeMemory = UInt64(stats.active_count) * pageSize
        let wiredMemory = UInt64(stats.wire_count) * pageSize

        let usedMemory = activeMemory + wiredMemory

        currentMemoryUsage = max(0.0, min(100.0, Double(usedMemory) / Double(totalMemory) * 100.0))
    }

    /// 获取内存使用率 (0.0 - 100.0) - 从缓存返回
    func getMemoryUsage() -> Double {
        return currentMemoryUsage
    }

    /// 获取格式化内存使用率字符串
    func getFormattedMemoryUsage() -> String {
        return String(format: "%.0f%%", currentMemoryUsage)
    }

    /// 获取已用内存（GB）
    func getUsedMemoryGB() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 0.0
        }

        let pageSize = Double(vm_kernel_page_size)
        let activeMemory = Double(stats.active_count) * pageSize
        let wiredMemory = Double(stats.wire_count) * pageSize

        return (activeMemory + wiredMemory) / (1024 * 1024 * 1024)
    }

    /// 获取总内存（GB）
    func getTotalMemoryGB() -> Double {
        return Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }
}
