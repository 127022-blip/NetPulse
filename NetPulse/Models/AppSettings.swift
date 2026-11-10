import Foundation

/// 应用设置模型
struct AppSettings: Codable {
    /// 菜单栏显示模式
    var menuBarDisplayMode: MenuBarDisplayMode = .iconAndSystem

    /// 外观主题：跟随系统 / 浅色 / 深色
    var appearanceMode: AppearanceMode = .system

    /// 更新间隔 (秒)
    var updateInterval: Double = 2.0

    /// 通知总开关
    var notificationsEnabled: Bool = true

    /// 断网通知是否启用
    var disconnectNotificationEnabled: Bool = true

    /// 速度告警阈值 (bytes per second)
    var speedThreshold: Double = 100 * 1024  // 100 KB/s

    /// 速度告警是否启用
    var speedAlertEnabled: Bool = false

    /// 选中的网络接口名称 (空字符串表示自动)
    var selectedInterface: String = ""

    /// 启动时自动运行
    var launchAtLogin: Bool = false

    /// 每日流量限制 (bytes)，默认 1GB
    var dailyTrafficLimit: UInt64 = 1024 * 1024 * 1024

    /// 流量提醒是否启用
    var trafficAlertEnabled: Bool = false


    /// 外观主题
    enum AppearanceMode: Int, Codable, Hashable {
        case system = 0
        case light = 1
        case dark = 2

        var displayName: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }

        static var allCases: [AppearanceMode] {
            [.system, .light, .dark]
        }
    }

    /// 菜单栏显示模式枚举
    /// rawValue 保持兼容：2 仍表示「原上下速度+系统」→ 现名「网速 + 系统」
    enum MenuBarDisplayMode: Int, Codable, Hashable {
        case iconOnly = 0              // 仅图标
        case iconAndSpeed = 1          // 图标 + 下载速度
        case iconAndSystem = 2         // 网速 + CPU/MEM/SSD（原 iconAndDualSpeed 渲染）
        case iconWithCPU = 3           // 图标 + CPU
        case iconAndDualSpeed = 4      // 图标 + 上下速度（纯网速，无系统指标）

        var displayName: String {
            switch self {
            case .iconOnly: return "仅图标"
            case .iconAndSpeed: return "图标 + 下载速度"
            case .iconAndSystem: return "网速 + 系统"
            case .iconWithCPU: return "图标 + CPU"
            case .iconAndDualSpeed: return "图标 + 上下速度"
            }
        }

        /// 选项副标题（设置页说明）
        var subtitle: String {
            switch self {
            case .iconOnly: return "菜单栏只显示应用图标"
            case .iconAndSpeed: return "图标旁显示下载速度"
            case .iconAndSystem: return "上下网速 + CPU / 内存 / 磁盘 + 温度"
            case .iconWithCPU: return "图标旁显示 CPU 占用与温度"
            case .iconAndDualSpeed: return "图标旁显示上传与下载速度"
            }
        }

        /// 推荐默认项
        var isRecommended: Bool { self == .iconAndSystem }

        /// 是否在菜单栏（及设置预览）显示程序 AppIcon
        /// 「网速 + 系统」为密集指标，不附带左侧图标
        var showsMenuBarAppIcon: Bool {
            switch self {
            case .iconAndSystem: return false
            case .iconOnly, .iconAndSpeed, .iconAndDualSpeed, .iconWithCPU: return true
            }
        }

        /// 兼容旧存档：若解码失败由外层默认；若旧名映射需要可在此扩展
        static var allCases: [MenuBarDisplayMode] {
            [.iconOnly, .iconAndSpeed, .iconAndDualSpeed, .iconAndSystem, .iconWithCPU]
        }
    }

    /// 自定义解码：丢掉已删除字段（runInBackground / miniWindowFloats），兼容旧 JSON
    enum CodingKeys: String, CodingKey {
        case menuBarDisplayMode, appearanceMode, updateInterval, notificationsEnabled
        case disconnectNotificationEnabled, speedThreshold, speedAlertEnabled
        case selectedInterface, launchAtLogin, dailyTrafficLimit, trafficAlertEnabled
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        menuBarDisplayMode = try c.decodeIfPresent(MenuBarDisplayMode.self, forKey: .menuBarDisplayMode) ?? defaults.menuBarDisplayMode
        appearanceMode = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode) ?? defaults.appearanceMode
        // 兼容：旧版 raw 2 名为 iconAndDualSpeed，现映射为 iconAndSystem（同 rawValue）
        updateInterval = try c.decodeIfPresent(Double.self, forKey: .updateInterval) ?? defaults.updateInterval
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? defaults.notificationsEnabled
        disconnectNotificationEnabled = try c.decodeIfPresent(Bool.self, forKey: .disconnectNotificationEnabled) ?? defaults.disconnectNotificationEnabled
        speedThreshold = try c.decodeIfPresent(Double.self, forKey: .speedThreshold) ?? defaults.speedThreshold
        speedAlertEnabled = try c.decodeIfPresent(Bool.self, forKey: .speedAlertEnabled) ?? defaults.speedAlertEnabled
        selectedInterface = try c.decodeIfPresent(String.self, forKey: .selectedInterface) ?? defaults.selectedInterface
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        dailyTrafficLimit = try c.decodeIfPresent(UInt64.self, forKey: .dailyTrafficLimit) ?? defaults.dailyTrafficLimit
        trafficAlertEnabled = try c.decodeIfPresent(Bool.self, forKey: .trafficAlertEnabled) ?? defaults.trafficAlertEnabled
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Constants.UserDefaultsKeys.appSettings)
        }
    }

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
