import Foundation
import Combine
import SwiftUI

/// 设置视图模型
final class SettingsViewModel: ObservableObject {
    // MARK: - Published 属性

    /// 菜单栏显示模式
    @Published var menuBarDisplayMode: AppSettings.MenuBarDisplayMode {
        didSet { saveSettings() }
    }

    /// 更新间隔 (秒)
    @Published var updateInterval: Double {
        didSet { saveSettings() }
    }

    /// 通知开关
    @Published var notificationsEnabled: Bool {
        didSet {
            saveSettings()
            if notificationsEnabled {
                requestNotificationPermission()
            }
        }
    }

    /// 断网通知开关
    @Published var disconnectNotificationEnabled: Bool {
        didSet { saveSettings() }
    }

    /// 速度告警开关
    @Published var speedAlertEnabled: Bool {
        didSet { saveSettings() }
    }

    /// 速度告警阈值 (KB/s)
    @Published var speedThresholdKB: Double {
        didSet { saveSettings() }
    }

    /// 选中的网络接口
    @Published var selectedInterface: String {
        didSet { saveSettings() }
    }

    /// 可用的网络接口列表
    @Published var availableInterfaces: [NetworkInterface] = []

    /// 后台运行开关
    @Published var runInBackground: Bool {
        didSet { saveSettings() }
    }

    /// 启动时自动运行
    @Published var launchAtLogin: Bool {
        didSet { saveSettings() }
    }

    /// 迷你窗口置顶
    @Published var miniWindowFloats: Bool {
        didSet { saveSettings() }
    }

    /// 通知授权状态
    @Published var isNotificationAuthorized: Bool = false

    // MARK: - 私有属性
    private var settings: AppSettings
    private let notificationService = NotificationService.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化
    init(settings: AppSettings = AppSettings.load()) {
        self.settings = settings
        self.menuBarDisplayMode = settings.menuBarDisplayMode
        self.updateInterval = settings.updateInterval
        self.notificationsEnabled = settings.notificationsEnabled
        self.disconnectNotificationEnabled = settings.disconnectNotificationEnabled
        self.speedAlertEnabled = settings.speedAlertEnabled
        self.speedThresholdKB = settings.speedThreshold / 1024
        self.selectedInterface = settings.selectedInterface
        self.runInBackground = settings.runInBackground
        self.launchAtLogin = settings.launchAtLogin
        self.miniWindowFloats = settings.miniWindowFloats

        setupBindings()
    }

    // MARK: - 公开方法

    /// 获取当前设置
    func getSettings() -> AppSettings {
        return settings
    }

    /// 刷新网络接口列表
    func refreshInterfaces() {
        // 暂时留空
    }

    /// 请求通知权限
    func requestNotificationPermission() {
        notificationService.requestAuthorization { [weak self] granted in
            DispatchQueue.main.async {
                self?.isNotificationAuthorized = granted
            }
        }
    }

    /// 重置所有设置为默认值
    func resetToDefaults() {
        let defaultSettings = AppSettings()
        menuBarDisplayMode = defaultSettings.menuBarDisplayMode
        updateInterval = defaultSettings.updateInterval
        notificationsEnabled = defaultSettings.notificationsEnabled
        disconnectNotificationEnabled = defaultSettings.disconnectNotificationEnabled
        speedAlertEnabled = defaultSettings.speedAlertEnabled
        speedThresholdKB = defaultSettings.speedThreshold / 1024
        selectedInterface = defaultSettings.selectedInterface
        runInBackground = defaultSettings.runInBackground
        launchAtLogin = defaultSettings.launchAtLogin
        miniWindowFloats = defaultSettings.miniWindowFloats
    }

    /// 导出设置 (用于调试)
    func exportSettings() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(settings),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "无法导出设置"
    }

    // MARK: - 私有方法

    /// 设置数据绑定
    private func setupBindings() {
        notificationService.$isAuthorized
            .receive(on: DispatchQueue.main)
            .assign(to: &$isNotificationAuthorized)
    }

    /// 保存设置
    private func saveSettings() {
        settings.menuBarDisplayMode = menuBarDisplayMode
        settings.updateInterval = updateInterval
        settings.notificationsEnabled = notificationsEnabled
        settings.disconnectNotificationEnabled = disconnectNotificationEnabled
        settings.speedAlertEnabled = speedAlertEnabled
        settings.speedThreshold = speedThresholdKB * 1024
        settings.selectedInterface = selectedInterface
        settings.runInBackground = runInBackground
        settings.launchAtLogin = launchAtLogin
        settings.miniWindowFloats = miniWindowFloats
        settings.save()
    }
}
