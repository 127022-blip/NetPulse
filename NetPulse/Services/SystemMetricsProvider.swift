import Foundation

/// 系统指标不可变快照
struct SystemMetricsSnapshot: Equatable {
    let cpuPercent: Double
    let memPercent: Double
    let diskPercent: Double
    let cpuText: String
    let memText: String
    let diskText: String
    let diskAvailable: Bool
}

/// 统一采样入口（可在后台队列调用），状态栏/面板共用
enum SystemMetricsProvider {
    static func sample() -> SystemMetricsSnapshot {
        let cpu = CPUMonitorService.shared.snapshot()
        let mem = MemoryMonitorService.shared.snapshot()
        let disk = DiskMonitorService.shared.snapshot()
        return SystemMetricsSnapshot(
            cpuPercent: cpu.percent,
            memPercent: mem.percent,
            diskPercent: disk.percent,
            cpuText: cpu.formatted,
            memText: mem.formatted,
            diskText: disk.formatted,
            diskAvailable: disk.available
        )
    }
}
