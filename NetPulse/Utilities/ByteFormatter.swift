import Foundation

/// 字节格式化工具
struct ByteFormatter {
    /// 速度单位枚举
    enum SpeedUnit: String {
        case B = "B/s"
        case KB = "KB/s"
        case MB = "MB/s"
        case GB = "GB/s"

        var bytesPerSecond: Double {
            switch self {
            case .B: return 1
            case .KB: return 1024
            case .MB: return 1024 * 1024
            case .GB: return 1024 * 1024 * 1024
            }
        }
    }

    /// 流量单位枚举
    enum TrafficUnit: String {
        case B = "B"
        case KB = "KB"
        case MB = "MB"
        case GB = "GB"
        case TB = "TB"

        var bytes: Double {
            switch self {
            case .B: return 1
            case .KB: return 1024
            case .MB: return 1024 * 1024
            case .GB: return 1024 * 1024 * 1024
            case .TB: return 1024 * 1024 * 1024 * 1024
            }
        }
    }

    /// 格式化速度为可读字符串 (自动选择单位)
    /// - Parameter bytesPerSecond: 每秒字节数
    /// - Returns: 格式化后的速度字符串，如 "1.23 MB/s"
    static func formatSpeed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "0 B/s" }

        if bytesPerSecond >= SpeedUnit.GB.bytesPerSecond {
            let value = bytesPerSecond / SpeedUnit.GB.bytesPerSecond
            return String(format: "%.2f %@", value, SpeedUnit.GB.rawValue)
        } else if bytesPerSecond >= SpeedUnit.MB.bytesPerSecond {
            let value = bytesPerSecond / SpeedUnit.MB.bytesPerSecond
            return String(format: "%.2f %@", value, SpeedUnit.MB.rawValue)
        } else if bytesPerSecond >= SpeedUnit.KB.bytesPerSecond {
            let value = bytesPerSecond / SpeedUnit.KB.bytesPerSecond
            return String(format: "%.2f %@", value, SpeedUnit.KB.rawValue)
        } else {
            return String(format: "%.0f %@", bytesPerSecond, SpeedUnit.B.rawValue)
        }
    }

    /// 格式化流量/数据大小为可读字符串 (自动选择单位)
    /// - Parameter bytes: 总字节数
    /// - Returns: 格式化后的流量字符串，如 "1.23 GB"
    static func formatBytes(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 B" }

        let doubleBytes = Double(bytes)

        if doubleBytes >= TrafficUnit.TB.bytes {
            let value = doubleBytes / TrafficUnit.TB.bytes
            return String(format: "%.2f %@", value, TrafficUnit.TB.rawValue)
        } else if doubleBytes >= TrafficUnit.GB.bytes {
            let value = doubleBytes / TrafficUnit.GB.bytes
            return String(format: "%.2f %@", value, TrafficUnit.GB.rawValue)
        } else if doubleBytes >= TrafficUnit.MB.bytes {
            let value = doubleBytes / TrafficUnit.MB.bytes
            return String(format: "%.2f %@", value, TrafficUnit.MB.rawValue)
        } else if doubleBytes >= TrafficUnit.KB.bytes {
            let value = doubleBytes / TrafficUnit.KB.bytes
            return String(format: "%.2f %@", value, TrafficUnit.KB.rawValue)
        } else {
            return String(format: "%.0f %@", doubleBytes, TrafficUnit.B.rawValue)
        }
    }

    /// 格式化速度为紧凑字符串 (用于菜单栏)
    /// - Parameter bytesPerSecond: 每秒字节数
    /// - Returns: 紧凑格式字符串，固定6字符宽度，如 " 123KB/S"（6字符）或 "   1MB/S"（6字符）
    static func formatSpeedCompact(_ bytesPerSecond: Double) -> String {
        let kbValue = bytesPerSecond / SpeedUnit.KB.bytesPerSecond
        
        if kbValue >= 1000 {
            // 超过999KB/S用MB/S显示
            let mbValue = kbValue / 1024
            return String(format: "%4dMB/S", Int(mbValue))
        } else {
            // KB/S显示，整数，固定6字符宽度
            return String(format: "%4dKB/S", Int(kbValue))
        }
    }

    /// 解析速度字符串为字节数
    /// - Parameter speedString: 速度字符串，如 "1.5MB/s"
    /// - Returns: 每秒字节数，解析失败返回 0
    static func parseSpeed(_ speedString: String) -> Double {
        var valueString = speedString.trimmingCharacters(in: .whitespaces)
        var unitString = ""

        // 提取数值和单位
        for unit in [SpeedUnit.GB, SpeedUnit.MB, SpeedUnit.KB, SpeedUnit.B] {
            let rawValue = unit.rawValue.replacingOccurrences(of: "/s", with: "")
            if valueString.hasSuffix(rawValue) {
                unitString = rawValue
                valueString = String(valueString.dropLast(rawValue.count))
                break
            }
        }

        guard let value = Double(valueString.trimmingCharacters(in: .whitespaces)) else {
            return 0
        }

        switch unitString {
        case "GB": return value * SpeedUnit.GB.bytesPerSecond
        case "MB": return value * SpeedUnit.MB.bytesPerSecond
        case "KB": return value * SpeedUnit.KB.bytesPerSecond
        default: return value
        }
    }
}
