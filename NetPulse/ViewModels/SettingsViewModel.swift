import Foundation
import Combine
import SwiftUI
import AppKit

/// 设置视图模型：滑条/数值字段 debounce 后落盘；避免拖动时狂刷 settingsChanged
final class SettingsViewModel: ObservableObject {
    @Published var menuBarDisplayMode: AppSettings.MenuBarDisplayMode {
        didSet { schedulePersist() }
    }

    @Published var updateInterval: Double {
        didSet { schedulePersist() }
    }

    @Published var speedAlertEnabled: Bool {
        didSet { schedulePersist() }
    }

    @Published var speedThresholdKBps: Double {
        didSet {
            if !suppressDraftSync {
                speedThresholdText = Self.formatSpeedThreshold(speedThresholdKBps)
                speedThresholdError = ""
            }
            schedulePersist()
        }
    }

    @Published var speedThresholdText: String = "" {
        didSet {
            if !suppressDraftSync {
                validateSpeedThresholdDraft()
            }
        }
    }

    @Published var speedThresholdError: String = ""

    @Published var disconnectNotificationEnabled: Bool {
        didSet { schedulePersist() }
    }

    @Published var notificationsEnabled: Bool {
        didSet { schedulePersist() }
    }

    @Published var selectedInterface: String {
        didSet { schedulePersist() }
    }

    @Published var availableInterfaces: [NetworkInterface] = []
    @Published var isRefreshingInterfaces: Bool = false
    @Published var interfacesRefreshMessage: String = ""

    @Published var launchAtLogin: Bool {
        didSet {
            schedulePersist()
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
        didSet { schedulePersist() }
    }

    @Published var dailyTrafficLimitGB: Double {
        didSet {
            if !suppressDraftSync {
                dailyTrafficLimitText = Self.formatDailyLimit(dailyTrafficLimitGB)
                dailyTrafficLimitError = ""
            }
            schedulePersist()
        }
    }

    @Published var dailyTrafficLimitText: String = "" {
        didSet {
            if !suppressDraftSync {
                validateDailyTrafficLimitDraft()
            }
        }
    }

    @Published var dailyTrafficLimitError: String = ""
    @Published var isNotificationAuthorized: Bool = false
    @Published var notificationAuthStatusText: String = "尚未请求"

    /// 告警子项默认折叠
    @Published var alertsExpanded: Bool = false
    /// 精确输入折叠（阈值降噪）
    @Published var showSpeedPreciseInput: Bool = false
    @Published var showTrafficPreciseInput: Bool = false

    let intervalOptions: [Double] = [1.0, 2.0, 3.0, 5.0]

    private var settings: AppSettings
    private let notificationService = NotificationService.shared
    private var cancellables = Set<AnyCancellable>()
    private var suppressPersist = false
    private var suppressDraftSync = false
    private let persistSubject = PassthroughSubject<Void, Never>()
    /// 最近一次已广播的 updateInterval，供网络层判断是否重建 Timer
    private var lastBroadcastInterval: Double

    init(settings: AppSettings = AppSettings.load()) {
        self.settings = settings
        self.menuBarDisplayMode = settings.menuBarDisplayMode
        self.updateInterval = settings.updateInterval
        self.lastBroadcastInterval = settings.updateInterval
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
        refreshNotificationStatus()
        refreshInterfaces()
    }

    private static let speedThresholdRange: ClosedRange<Double> = 10...1024
    private static let dailyLimitRange: ClosedRange<Double> = 0.5...100

    private static func formatSpeedThreshold(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private static func formatDailyLimit(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// 子告警是否可交互：总开关开且系统已授权
    var alertControlsEnabled: Bool {
        notificationsEnabled && isNotificationAuthorized
    }

    func refreshNotificationStatus() {
        notificationService.checkAuthorizationStatus()
    }

    func validateSpeedThresholdDraft() {
        let trimmed = speedThresholdText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            speedThresholdError = "请输入数值"
            return
        }
        guard let parsed = Double(trimmed), parsed.isFinite else {
            speedThresholdError = "请输入有效数字"
            return
        }
        if parsed < Self.speedThresholdRange.lowerBound || parsed > Self.speedThresholdRange.upperBound {
            speedThresholdError = "范围须为 10–1024 KB/s"
            return
        }
        speedThresholdError = ""
    }

    func validateDailyTrafficLimitDraft() {
        let trimmed = dailyTrafficLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            dailyTrafficLimitError = "请输入数值"
            return
        }
        guard let parsed = Double(trimmed), parsed.isFinite else {
            dailyTrafficLimitError = "请输入有效数字"
            return
        }
        if parsed < Self.dailyLimitRange.lowerBound || parsed > Self.dailyLimitRange.upperBound {
            dailyTrafficLimitError = "范围须为 0.5–100 GB"
            return
        }
        dailyTrafficLimitError = ""
    }

    func commitSpeedThreshold() {
        validateSpeedThresholdDraft()
        let trimmed = speedThresholdText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard speedThresholdError.isEmpty, let parsed = Double(trimmed), parsed.isFinite else {
            suppressDraftSync = true
            speedThresholdText = Self.formatSpeedThreshold(speedThresholdKBps)
            suppressDraftSync = false
            speedThresholdError = ""
            return
        }
        let clamped = min(max(parsed, Self.speedThresholdRange.lowerBound), Self.speedThresholdRange.upperBound)
        suppressDraftSync = true
        speedThresholdKBps = clamped
        speedThresholdText = Self.formatSpeedThreshold(clamped)
        suppressDraftSync = false
        speedThresholdError = ""
        flushPersist()
    }

    func commitDailyTrafficLimit() {
        validateDailyTrafficLimitDraft()
        let trimmed = dailyTrafficLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard dailyTrafficLimitError.isEmpty, let parsed = Double(trimmed), parsed.isFinite else {
            suppressDraftSync = true
            dailyTrafficLimitText = Self.formatDailyLimit(dailyTrafficLimitGB)
            suppressDraftSync = false
            dailyTrafficLimitError = ""
            return
        }
        let clamped = min(max(parsed, Self.dailyLimitRange.lowerBound), Self.dailyLimitRange.upperBound)
        suppressDraftSync = true
        dailyTrafficLimitGB = clamped
        dailyTrafficLimitText = Self.formatDailyLimit(clamped)
        suppressDraftSync = false
        dailyTrafficLimitError = ""
        flushPersist()
    }

    func getSettings() -> AppSettings { settings }

    func requestNotificationPermission() {
        notificationService.requestAuthorization { [weak self] granted in
            DispatchQueue.main.async {
                self?.isNotificationAuthorized = granted
                self?.notificationAuthStatusText = self?.notificationService.authorizationStatusText ?? (granted ? "已授权" : "已拒绝")
                if !granted {
                    // 拒绝后仍可引导去系统设置
                    self?.refreshNotificationStatus()
                }
            }
        }
    }

    func openSystemNotificationSettings() {
        notificationService.openSystemNotificationSettings()
    }

    func resetToDefaults() {
        suppressPersist = true
        let d = AppSettings()
        menuBarDisplayMode = d.menuBarDisplayMode
        AppearancePreference.shared.adoptMode(d.appearanceMode)
        updateInterval = d.updateInterval
        speedAlertEnabled = d.speedAlertEnabled
        speedThresholdKBps = d.speedThreshold / 1024.0
        disconnectNotificationEnabled = d.disconnectNotificationEnabled
        notificationsEnabled = d.notificationsEnabled
        selectedInterface = d.selectedInterface
        launchAtLogin = d.launchAtLogin
        trafficAlertEnabled = d.trafficAlertEnabled
        dailyTrafficLimitGB = Double(d.dailyTrafficLimit) / (1024.0 * 1024.0 * 1024.0)
        suppressDraftSync = true
        speedThresholdText = Self.formatSpeedThreshold(speedThresholdKBps)
        dailyTrafficLimitText = Self.formatDailyLimit(dailyTrafficLimitGB)
        suppressDraftSync = false
        speedThresholdError = ""
        dailyTrafficLimitError = ""
        showSpeedPreciseInput = false
        showTrafficPreciseInput = false
        suppressPersist = false
        flushPersist()
        _ = LoginItemService.shared.update(enabled: launchAtLogin)
    }

    func resetTodayTraffic() {
        StorageService.shared.resetTodayTraffic()
    }

    func refreshInterfaces() {
        guard !isRefreshingInterfaces else { return }
        isRefreshingInterfaces = true
        interfacesRefreshMessage = ""
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let list = TrafficCalculator().getNetworkInterfacesSync()
            DispatchQueue.main.async {
                self?.availableInterfaces = list
                self?.isRefreshingInterfaces = false
                self?.interfacesRefreshMessage = "已刷新·共 \(list.count) 个"
            }
        }
    }

    private func setupBindings() {
        notificationService.$isAuthorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in
                self?.isNotificationAuthorized = granted
            }
            .store(in: &cancellables)

        notificationService.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.notificationAuthStatusText = self?.notificationService.authorizationStatusText ?? "未知"
            }
            .store(in: &cancellables)

        // 滑条/字段 debounce 280ms 后落盘并广播
        persistSubject
            .debounce(for: .milliseconds(280), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.persistNow()
            }
            .store(in: &cancellables)
    }

    private func schedulePersist() {
        guard !suppressPersist else { return }
        persistSubject.send(())
    }

    private func flushPersist() {
        guard !suppressPersist else { return }
        persistNow()
    }

    private func persistNow() {
        settings.menuBarDisplayMode = menuBarDisplayMode
        settings.appearanceMode = AppearancePreference.shared.appearanceMode
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
        lastBroadcastInterval = updateInterval
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
