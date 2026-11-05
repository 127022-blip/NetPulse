import Foundation

/// 硬盘使用率监控服务（带短时缓存，避免过频读盘）
final class DiskMonitorService {
    static let shared = DiskMonitorService()

    private var cachedUsage: Double = 0.0
    private var cachedTotal: Int64 = 0
    private var cachedFree: Int64 = 0
    private var cacheTimestamp: Date?
    private let cacheTTL: TimeInterval = 10.0

    private init() {}

    private func refreshIfNeeded() {
        if let ts = cacheTimestamp, Date().timeIntervalSince(ts) < cacheTTL {
            return
        }
        let fileManager = FileManager.default
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let totalSize = systemAttributes[.systemSize] as? Int64,
               let freeSize = systemAttributes[.systemFreeSize] as? Int64 {
                let usedSize = totalSize - freeSize
                let usage = Double(usedSize) / Double(totalSize) * 100.0
                cachedUsage = max(0.0, min(100.0, usage))
                cachedTotal = totalSize
                cachedFree = freeSize
                cacheTimestamp = Date()
                return
            }
        } catch {
            print("DiskMonitorService: Failed to get disk usage - \(error)")
        }
        cachedUsage = 0.0
        cachedTotal = 0
        cachedFree = 0
        cacheTimestamp = Date()
    }

    /// 获取硬盘使用率百分比 (0-100)
    func getDiskUsage() -> Double {
        refreshIfNeeded()
        return cachedUsage
    }

    /// 获取格式化的硬盘使用率字符串 (如 "45%")
    func getFormattedDiskUsage() -> String {
        String(format: "%.0f%%", getDiskUsage())
    }

    /// 获取硬盘总容量 (字节)
    func getTotalDiskSpace() -> Int64 {
        refreshIfNeeded()
        return cachedTotal
    }

    /// 获取硬盘可用容量 (字节)
    func getFreeDiskSpace() -> Int64 {
        refreshIfNeeded()
        return cachedFree
    }
}
