import Foundation

/// 硬盘使用率监控：失败时保留上次成功值；从未成功则 available=false 显示 --%
final class DiskMonitorService {
    static let shared = DiskMonitorService()

    struct Snapshot: Equatable {
        let percent: Double
        let formatted: String
        let available: Bool
        let total: Int64
        let free: Int64
    }

    private let lock = NSLock()
    private var cachedUsage: Double = 0.0
    private var cachedTotal: Int64 = 0
    private var cachedFree: Int64 = 0
    private var hasSuccessfulSample = false
    private var cacheTimestamp: Date?
    private let cacheTTL: TimeInterval = 10.0

    private init() {}

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        refreshIfNeededLocked()
        if hasSuccessfulSample {
            return Snapshot(
                percent: cachedUsage,
                formatted: String(format: "%.0f%%", cachedUsage),
                available: true,
                total: cachedTotal,
                free: cachedFree
            )
        }
        return Snapshot(percent: 0, formatted: "--%", available: false, total: 0, free: 0)
    }

    func getDiskUsage() -> Double { snapshot().percent }
    func getFormattedDiskUsage() -> String { snapshot().formatted }
    func getTotalDiskSpace() -> Int64 { snapshot().total }
    func getFreeDiskSpace() -> Int64 { snapshot().free }

    private func refreshIfNeededLocked() {
        if let ts = cacheTimestamp, Date().timeIntervalSince(ts) < cacheTTL {
            return
        }
        let fileManager = FileManager.default
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let totalSize = systemAttributes[.systemSize] as? Int64,
               let freeSize = systemAttributes[.systemFreeSize] as? Int64,
               totalSize > 0 {
                let usedSize = totalSize - freeSize
                let usage = Double(usedSize) / Double(totalSize) * 100.0
                cachedUsage = max(0.0, min(100.0, usage))
                cachedTotal = totalSize
                cachedFree = freeSize
                hasSuccessfulSample = true
                cacheTimestamp = Date()
                return
            }
        } catch {
            NetPulseLog.error("DiskMonitorService 读取失败: \(error.localizedDescription)")
        }
        // 失败：不把缓存写成 0%；仅刷新时间戳避免狂刷，保留上次成功
        cacheTimestamp = Date()
    }
}
