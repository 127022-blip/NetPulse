import Foundation
import Combine
import SwiftUI

/// 设置视图模型
final class SettingsViewModel: ObservableObject {
    @Published var menuBarDisplayMode: AppSettings.MenuBarDisplayMode {
        didSet { persist() }
    }

    @Published var appearanceMode: AppSettings.AppearanceMode {
        didSet { persist() }
    }

    @Published var updateInterval: Double {
        didSet { persist() }
    }

    @Published var speedAlertEnabled: Bool {
        didSet { persist() }
    }

    @Published var speedThresholdKBps: Double {
        didSet {
            if !suppressDraftSync {
                speedThresholdText = Self.formatSpeedThreshold(speedThresholdKBps)
            }
            persist()
        }
    }

    /// 告警阈值输入框草稿（KB/s）
    @Published var speedThresholdText: String = ""

    @Published var disconnectNotificationEnabled: Bool {
        didSet { persist() }
    }

    @Published var notificationsEnabled: Bool {
        didSet { persist() }
    }

    @Published var selectedInterface: String {
        didSet { persist() }
    }

    @Published var availableInterfaces: [NetworkInterface] = []

    @Published var launchAtLogin: Bool {
        didSet {
            persist()
            let ok = LoginItemService.shared.update(enabled: launchAtLogin)
            if launchAtLogin && !ok {
                launchAtLoginHint = LoginItemService.shared.lastErrorMessage ?? "登录项设置失败，请在「系统设置 → 通用 → 登录项」中手动添加。"
            } else {
                launchAtLoginHint = ok ? "" : (LoginItemService.shared.lastErrorMessage ?? "")
            }
        }
    }

    @Published var launchAtLoginHint: String = ""

    @Published var trafficAlertEnabled: Bool {
        didSet { persist() }
    }

    /// 日限额（GB，界面用）
    @Published var dailyTrafficLimitGB: Double {
        didSet {
            if !suppressDraftSync {
                dailyTrafficLimitText = Self.formatDailyLimit(dailyTrafficLimitGB)
            }
            persist()
        }
    }

    /// 日限额输入框草稿（GB）
    @Published var dailyTrafficLimitText: String = ""

    @Published var isNotificationAuthorized: Bool = false

    let intervalOptions: [Double] = [1.0, 2.0, 3.0, 5.0]

    private var settings: AppSettings
    private let notificationService = NotificationService.shared
    private var cancellables = Set<AnyCancellable>()
    private var suppressPersist = false
    private var suppressDraftSync = false

    init(settings: AppSettings = AppSettings.load()) {
        self.settings = settings
        self.menuBarDisplayMode = settings.menuBarDisplayMode
        self.appearanceMode = settings.appearanceMode
        self.updateInterval = settings.updateInterval
        self.speedAlertEnabled = settings.speedAlertEnabled
        self.speedThresholdKBps = settings.speedThreshold / 1024.0
        self.disconnectNotificationEnabled = settings.disconnectNotificationEnabled
        self.notificationsEnabled = settings.notificationsEnabled
        self.selectedInterface = settings.selectedInterface
        self.launchAtLogin = settings.launchAtLogin
        self.trafficAlertEnabled = settings.trafficAlertEnabled
        self.dailyTrafficLimitGB = Double(settings.dailyTrafficLimit) / (1024.0 * 1024.0 * 1024.0)
        self.speedThresholdText = Self.formatSpeedThreshold(self.speedThresholdKBps)
        self.dailyTrafficLimitText = Self.formatDailyLimit(self.dailyTrafficLimitGB)

        setupBindings()
        refreshInterfaces()
    }

    // MARK: - 滑条旁可编辑数值

    private static let speedThresholdRange: ClosedRange<Double> = 10...1024
    private static let dailyLimitRange: ClosedRange<Double> = 0.5...100

    private static func formatSpeedThreshold(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private static func formatDailyLimit(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// 提交告警阈值输入；非法/空则回退为当前有效值
    func commitSpeedThreshold() {
        let trimmed = speedThresholdText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = Double(trimmed), parsed.isFinite else {
            speedThresholdText = Self.formatSpeedThreshold(speedThresholdKBps)
            return
        }
        let clamped = min(max(parsed, Self.speedThresholdRange.lowerBound), Self.speedThresholdRange.upperBound)
        suppressDraftSync = true
        speedThresholdKBps = clamped
        suppressDraftSync = false
        speedThresholdText = Self.formatSpeedThreshold(clamped)
    }

    /// 提交日限额输入；非法/空则回退为当前有效值
    func commitDailyTrafficLimit() {
        let trimmed = dailyTrafficLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = Double(trimmed), parsed.isFinite else {
            dailyTrafficLimitText = Self.formatDailyLimit(dailyTrafficLimitGB)
            return
        }
        let clamped = min(max(parsed, Self.dailyLimitRange.lowerBound), Self.dailyLimitRange.upperBound)
        suppressDraftSync = true
        dailyTrafficLimitGB = clamped
        suppressDraftSync = false
        dailyTrafficLimitText = Self.formatDailyLimit(clamped)
    }

    func getSettings() -> AppSettings { settings }

    func requestNotificationPermission() {
        notificationService.requestAuthorization { [weak self] granted in
            DispatchQueue.main.async {
                self?.isNotificationAuthorized = granted
            }
        }
    }

    func resetToDefaults() {
        suppressPersist = true
        let d = AppSettings()
        menuBarDisplayMode = d.menuBarDisplayMode
        appearanceMode = d.appearanceMode
        updateInterval = d.updateInterval
        speedAlertEnabled = d.speedAlertEnabled
        speedThresholdKBps = d.speedThreshold / 1024.0
        disconnectNotificationEnabled = d.disconnectNotificationEnabled
        notificationsEnabled = d.notificationsEnabled
        selectedInterface = d.selectedInterface
        launchAtLogin = d.launchAtLogin
        trafficAlertEnabled = d.trafficAlertEnabled
        dailyTrafficLimitGB = Double(d.dailyTrafficLimit) / (1024.0 * 1024.0 * 1024.0)
        speedThresholdText = Self.formatSpeedThreshold(speedThresholdKBps)
        dailyTrafficLimitText = Self.formatDailyLimit(dailyTrafficLimitGB)
        suppressPersist = false
        persist()
        _ = LoginItemService.shared.update(enabled: launchAtLogin)
    }

    func resetTodayTraffic() {
        StorageService.shared.resetTodayTraffic()
    }

    func refreshInterfaces() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let list = TrafficCalculator().getNetworkInterfacesSync()
            DispatchQueue.main.async {
                self?.availableInterfaces = list
            }
        }
    }

    private func setupBindings() {
        notificationService.$isAuthorized
            .receive(on: DispatchQueue.main)
            .assign(to: &$isNotificationAuthorized)
    }

    private func persist() {
        guard !suppressPersist else { return }
        settings.menuBarDisplayMode = menuBarDisplayMode
        settings.appearanceMode = appearanceMode
        settings.updateInterval = updateInterval
        settings.speedAlertEnabled = speedAlertEnabled
        settings.speedThreshold = max(speedThresholdKBps, 1) * 1024.0
        settings.disconnectNotificationEnabled = disconnectNotificationEnabled
        settings.notificationsEnabled = notificationsEnabled
        settings.selectedInterface = selectedInterface
        settings.launchAtLogin = launchAtLogin
        settings.trafficAlertEnabled = trafficAlertEnabled
        settings.dailyTrafficLimit = UInt64(max(dailyTrafficLimitGB, 0.1) * 1024 * 1024 * 1024)
        settings.save()
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
