import Foundation

/// 应用常量定义
enum Constants {
    /// UserDefaults 键名
    enum UserDefaultsKeys {
        static let appSettings = "com.netpulse.appSettings"
        static let todayDownloadBytes = "todayDownloadBytes"
        static let todayUploadBytes = "todayUploadBytes"
        static let lastResetDate = "lastResetDate"
        static let trafficRecords = "trafficRecords"
    }

    /// 应用信息
    enum App {
        static let name = "NetPulse"
        static let bundleIdentifier = "com.netpulse.app"
        static let version = "1.0.0"
        static let build = "1"
    }

    /// 界面常量
    enum UI {
        static let menuBarIconSize: CGFloat = 18
        static let panelWidth: CGFloat = 320
        static let panelCornerRadius: CGFloat = 12
        static let animationDuration: Double = 0.25
    }

    /// 网络常量
    enum Network {
        static let defaultUpdateInterval: Double = 1.0  // 秒
        static let minSpeedThreshold: Double = 1024  // 1 KB/s
        static let defaultSpeedThreshold: Double = 100 * 1024  // 100 KB/s
    }

    /// 存储常量
    enum Storage {
        static let maxHistoryDays = 30  // 保留30天历史记录
        static let saveInterval: Double = 60  // 每60秒保存一次
    }
}

/// 日期格式化工具
extension DateFormatter {
    /// 年-月-日 格式化 (YYYY-MM-DD)
    static let yearMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()

    /// 时:分:秒 格式化 (HH:mm:ss)
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()

    /// 完整的日期时间格式化
    static let fullDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()
}

/// ISO8601 日期格式化
let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()
