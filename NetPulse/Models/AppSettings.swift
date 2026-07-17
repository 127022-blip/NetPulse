import Foundation

/// 应用设置模型
struct AppSettings: Codable {
    /// 菜单栏显示模式
    var menuBarDisplayMode: MenuBarDisplayMode = .iconAndSpeed

    /// 更新间隔 (秒)
    var updateInterval: Double = 2.0

    /// 是否显示通知
    var notificationsEnabled: Bool = true

    /// 断网通知是否启用
    var disconnectNotificationEnabled: Bool = true

    /// 速度告警阈值 (bytes per second)
    var speedThreshold: Double = 100 * 1024  // 100 KB/s

    /// 速度告警是否启用
    var speedAlertEnabled: Bool = false

    /// 选中的网络接口名称 (空字符串表示自动)
    var selectedInterface: String = ""

    /// 是否在后台运行
    var runInBackground: Bool = true

    /// 启动时自动运行
    var launchAtLogin: Bool = false

    /// 迷你窗口是否置顶
    var miniWindowFloats: Bool = true

    /// 每日流量限制 (bytes)，默认 1GB
    var dailyTrafficLimit: UInt64 = 1024 * 1024 * 1024

    /// 流量提醒是否启用
    var trafficAlertEnabled: Bool = false

    /// 菜单栏显示模式枚举
    enum MenuBarDisplayMode: Int, Codable, CaseIterable {
        case iconOnly = 0           // 仅图标
        case iconAndSpeed = 1       // 图标 + 速度
        case iconAndDualSpeed = 2   // 图标 + 上下速度

        var displayName: String {
            switch self {
            case .iconOnly: return "仅图标"
            case .iconAndSpeed: return "图标 + 速度"
            case .iconAndDualSpeed: return "图标 + 上下速度"
            }
        }
    }

    /// 保存设置到 UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Constants.UserDefaultsKeys.appSettings)
        }
    }

    /// 从 UserDefaults 加载设置
    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: Constants.UserDefaultsKeys.appSettings),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }
}

/// 通知类型枚举
enum NotificationType: String, CaseIterable {
    case disconnect = "disconnect"
    case reconnect = "reconnect"
    case slowSpeed = "slowSpeed"
    case highTraffic = "highTraffic"

    var title: String {
        switch self {
        case .disconnect: return "网络已断开"
        case .reconnect: return "网络已恢复"
        case .slowSpeed: return "网速较慢"
        case .highTraffic: return "流量提醒"
        }
    }

    var systemImage: String {
        switch self {
        case .disconnect: return "wifi.slash"
        case .reconnect: return "wifi"
        case .slowSpeed: return "speedometer"
        case .highTraffic: return "exclamationmark.triangle"
        }
    }
}
