import Foundation

/// 硬盘使用率监控服务
final class DiskMonitorService {
    static let shared = DiskMonitorService()

    private init() {}

    /// 获取硬盘使用率百分比 (0-100)
    func getDiskUsage() -> Double {
        let fileManager = FileManager.default
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let totalSize = systemAttributes[.systemSize] as? Int64,
               let freeSize = systemAttributes[.systemFreeSize] as? Int64 {
                let usedSize = totalSize - freeSize
                let usage = Double(usedSize) / Double(totalSize) * 100.0
                return max(0.0, min(100.0, usage))
            }
        } catch {
            print("DiskMonitorService: Failed to get disk usage - \(error)")
        }
        return 0.0
    }

    /// 获取格式化的硬盘使用率字符串 (如 "45%")
    func getFormattedDiskUsage() -> String {
        let usage = getDiskUsage()
        return String(format: "%.0f%%", usage)
    }

    /// 获取硬盘总容量 (字节)
    func getTotalDiskSpace() -> Int64 {
        let fileManager = FileManager.default
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let totalSize = systemAttributes[.systemSize] as? Int64 {
                return totalSize
            }
        } catch {
            print("DiskMonitorService: Failed to get total disk space - \(error)")
        }
        return 0
    }

    /// 获取硬盘可用容量 (字节)
    func getFreeDiskSpace() -> Int64 {
        let fileManager = FileManager.default
        do {
            let systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSize = systemAttributes[.systemFreeSize] as? Int64 {
                return freeSize
            }
        } catch {
            print("DiskMonitorService: Failed to get free disk space - \(error)")
        }
        return 0
    }
}
