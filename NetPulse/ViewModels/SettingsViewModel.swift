import Foundation
import Combine
import SwiftUI

/// 设置视图模型
final class SettingsViewModel: ObservableObject {
    // MARK: - Published 属性

    /// 后台运行开关
    @Published var runInBackground: Bool {
        didSet {
            saveSettings()
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    /// 启动时自动运行
    @Published var launchAtLogin: Bool {
        didSet {
            saveSettings()
            // 立即更新登录项状态
            LoginItemService.shared.update(enabled: launchAtLogin)
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
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
        self.runInBackground = settings.runInBackground
        self.launchAtLogin = settings.launchAtLogin

        setupBindings()
    }

    // MARK: - 公开方法

    /// 获取当前设置
    func getSettings() -> AppSettings {
        return settings
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
        runInBackground = defaultSettings.runInBackground
        launchAtLogin = defaultSettings.launchAtLogin
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
        settings.runInBackground = runInBackground
        settings.launchAtLogin = launchAtLogin
        settings.save()
    }
}
