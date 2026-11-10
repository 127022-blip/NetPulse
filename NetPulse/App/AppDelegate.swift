import AppKit
import SwiftUI
import Combine

/// 应用入口代理：编排 StatusBar / Popover / Window，自身保持精简
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: NetworkMonitorViewModel!
    private var networkService: NetworkMonitorService!
    private let statusBar = StatusBarController()
    private let popoverPresenter = PopoverPresenter()
    private let windowCoordinator = WindowCoordinator()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let existingApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        if existingApps.count > 1 {
            NetPulseLog.info("已有实例在运行，退出")
            NSApp.terminate(nil)
            return
        }

        setupServices()
        statusBar.install(target: self, action: #selector(statusBarButtonClicked(_:)))
        statusBar.bind(snapshotPublisher: viewModel.$statusBarSnapshot.eraseToAnyPublisher())
        // 首帧立刻画一次
        statusBar.apply(viewModel.statusBarSnapshot)

        popoverPresenter.setup(rootView: DropdownPanelView(viewModel: viewModel))
        startMonitoring()
        setupSleepWakeHandling()
        observeAppNotifications()

        if ProcessInfo.processInfo.arguments.contains("--show-about") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.windowCoordinator.showAbout()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stopMonitoring()
        StorageService.shared.saveTodayTraffic()
        popoverPresenter.close()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 弹窗已显示时保持 key
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Setup

    private func setupServices() {
        let settings = AppSettings.load()
        networkService = NetworkMonitorService(settings: settings)
        viewModel = NetworkMonitorViewModel(
            networkService: networkService,
            storageService: StorageService.shared,
            settings: settings
        )
        if settings.launchAtLogin {
            LoginItemService.shared.enable()
        }
    }

    private func startMonitoring() {
        NotificationService.shared.requestAuthorization()
        viewModel.startMonitoring()
    }

    private func observeAppNotifications() {
        NotificationCenter.default.publisher(for: .openSettings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.popoverPresenter.close()
                self?.windowCoordinator.showSettings()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .openAbout)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.popoverPresenter.close()
                self?.windowCoordinator.showAbout()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .settingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.viewModel.updateSettings()
                if self?.popoverPresenter.isShown == true {
                    self?.popoverPresenter.refreshFittingSize()
                }
            }
            .store(in: &cancellables)

        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.popoverPresenter.isShown else { return }
                self.popoverPresenter.refreshFittingSize()
            }
            .store(in: &cancellables)
    }

    private func setupSleepWakeHandling() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    @objc private func systemWillSleep() {
        popoverPresenter.close()
        networkService?.pauseForSleep()
    }

    @objc private func systemDidWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.networkService?.resumeAfterWake()
        }
    }

    // MARK: - 状态栏交互

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开面板", action: #selector(togglePopover), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let aboutItem = NSMenuItem(title: "关于 NetPulse", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusBar.showContextMenu(menu)
    }

    @objc private func togglePopover() {
        guard let button = statusBar.button else { return }
        popoverPresenter.toggle(relativeTo: button)
    }

    @objc private func showSettings() {
        popoverPresenter.close()
        windowCoordinator.showSettings()
    }

    @objc private func showAbout() {
        popoverPresenter.close()
        windowCoordinator.showAbout()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
