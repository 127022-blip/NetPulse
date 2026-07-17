import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // MARK: - 属性
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var viewModel: NetworkMonitorViewModel!
    private var networkService: NetworkMonitorService!
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private var aboutWindow: NSWindow?
    private var settingsWindow: NSWindow?

    // MARK: - 应用代理方法
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupServices()
        setupStatusItem()
        setupPopover()
        startMonitoring()
        startMenuBarUpdateTimer()
        setupEventMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stopMonitoring()
        StorageService.shared.saveTodayTraffic()
        updateTimer?.invalidate()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - NSApplicationDelegate
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - 私有方法
    private func setupServices() {
        let settings = AppSettings.load()
        networkService = NetworkMonitorService(settings: settings)
        viewModel = NetworkMonitorViewModel(
            networkService: networkService,
            storageService: StorageService.shared,
            settings: settings
        )

        // 同步登录项状态
        if settings.launchAtLogin {
            LoginItemService.shared.enable()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        updateButton(button)

        // 监听视图模型变化
        viewModel.$menuBarIcon
            .combineLatest(viewModel.$menuBarDualSpeedText)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] icon, dualSpeed in
                guard let btn = self?.statusItem?.button else { return }
                self?.updateButton(btn, icon: icon, dualSpeed: dualSpeed)
            }
            .store(in: &cancellables)

        // 设置按钮点击
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 340, height: 600)
        popover?.behavior = .transient
        popover?.animates = true

        let contentView = DropdownPanelView(viewModel: viewModel)
        popover?.contentViewController = NSHostingController(rootView: contentView)

        // 监听设置通知
        NotificationCenter.default.addObserver(
            forName: .openSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showSettings()
        }

        // 监听设置变更
        NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.viewModel.reloadSettings()
        }
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    private func updateButton(_ button: NSStatusBarButton, icon: String? = nil, speed: String? = nil, dualSpeed: String? = nil) {
        button.image = nil  // 不显示图标

        // 使用固定宽度格式确保数字不晃动
        let downSpeed = viewModel.menuBarSpeedText
        let upSpeed = viewModel.menuBarUploadSpeedText
        let cpuUsage = CPUMonitorService.shared.getFormattedCPUUsage()
        let memoryUsage = MemoryMonitorService.shared.getFormattedMemoryUsage()
        let diskUsage = DiskMonitorService.shared.getFormattedDiskUsage()

        // 创建固定宽度的 attributed string（三行显示）
        let attributedTitle = createFixedWidthSpeedText(down: downSpeed, up: upSpeed, cpu: cpuUsage, memory: memoryUsage, disk: diskUsage)
        button.attributedTitle = attributedTitle
    }

    // 创建固定宽度的速度显示（两行，左侧上下速度，右侧 CPU、内存、硬盘 信息）
    private func createFixedWidthSpeedText(down: String, up: String, cpu: String, memory: String, disk: String) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)

        // 使用 NSTextTab 固定制表位实现真正的列对齐
        // 第一列: 0 (左对齐，↑↓速度)
        // 第二列: 84 (右对齐，CPU数值/标签)
        // 第三列: 120 (右对齐，内存数值/标签)
        // 第四列: 144 (左对齐，硬盘数值/标签)
        let leftTab: CGFloat = 0
        let cpuTab: CGFloat = 84
        let memTab: CGFloat = 120
        let diskTab: CGFloat = 144

        // 创建带制表位的段落样式
        func createParagraphStyle() -> NSMutableParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.tabStops = [
                NSTextTab(textAlignment: .left, location: leftTab),
                NSTextTab(textAlignment: .right, location: cpuTab),
                NSTextTab(textAlignment: .right, location: memTab),
                NSTextTab(textAlignment: .left, location: diskTab)
            ]
            p.defaultTabInterval = cpuTab
            p.lineHeightMultiple = 0.8
            return p
        }

        let attrString = NSMutableAttributedString()

        // 第一行：↑速度 + \t + CPU数值 + \t + 内存数值 + \t + 硬盘数值
        let line1 = NSMutableAttributedString(string: "↑ " + up + "\t" + cpu + "\t" + memory + "\t" + disk, attributes: [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .baselineOffset: -1,
            .paragraphStyle: createParagraphStyle()
        ])
        attrString.append(line1)
        attrString.append(NSAttributedString(string: "\n"))

        // 第二行：↓速度 + \t + CPU标签 + \t + 内存标签 + \t + 硬盘标签
        let line2 = NSMutableAttributedString(string: "↓ " + down + "\tCPU\tMEM\tSSD", attributes: [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .baselineOffset: -1,
            .paragraphStyle: createParagraphStyle()
        ])
        attrString.append(line2)

        return attrString
    }
    
    // 创建垂直居中的 emoji 图片
    private func createCenteredEmojiImage(_ emoji: String) -> NSImage {
        // 使用状态栏标准高度，让系统自动处理垂直居中
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()
        
        let font = NSFont.systemFont(ofSize: 14)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor
        ]
        let attrString = NSAttributedString(string: emoji, attributes: attrs)
        let stringSize = attrString.size()
        // 居中放置，y坐标稍往下让两行文字更居中
        let point = NSPoint(
            x: (size.width - stringSize.width) / 2,
            y: (size.height - stringSize.height) / 2 + 1
        )
        attrString.draw(at: point)
        image.unlockFocus()
        return image
    }

    // 创建 emoji 图片
    private func createEmojiImage(_ emoji: String) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let font = NSFont.systemFont(ofSize: 14)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor
        ]
        let attrString = NSAttributedString(string: emoji, attributes: attrs)
        let stringSize = attrString.size()
        let point = NSPoint(
            x: (size.width - stringSize.width) / 2,
            y: (size.height - stringSize.height) / 2
        )
        attrString.draw(at: point)
        image.unlockFocus()
        return image
    }

    private func startMonitoring() {
        NotificationService.shared.requestAuthorization()
        viewModel.startMonitoring()
    }

    private func startMenuBarUpdateTimer() {
        // 每2秒更新一次网速和CPU
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let btn = self?.statusItem?.button else { return }
            self?.updateButton(btn)
        }
        RunLoop.main.add(updateTimer!, forMode: .common)
    }

    // MARK: - 按钮点击事件
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // 右键显示菜单
            showMenu()
        } else {
            // 左键显示/隐藏面板
            togglePopover()
        }
    }

    // MARK: - 菜单和面板
    private func showMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "打开面板", action: #selector(togglePopover), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "关于 NetPulse", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        if let button = statusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        }
        statusItem?.menu = nil
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            // 相对于按钮显示
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover?.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func showAbout() {
        // 如果窗口已存在，只显示到前面
        if aboutWindow != nil {
            aboutWindow?.makeKeyAndOrderFront(nil)
            return
        }

        // 创建自定义关于窗口
        let aboutView = AboutView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: aboutView)
        window.center()

        // 先设置窗口层级，再显示到前面
        window.level = .floating
        window.makeKeyAndOrderFront(nil)

        // 使用 delegate 处理窗口关闭
        window.delegate = self
        aboutWindow = window
    }

    @objc private func showSettings() {
        // 如果窗口已存在，只显示到前面
        if settingsWindow != nil {
            settingsWindow?.makeKeyAndOrderFront(nil)
            return
        }

        let settingsViewModel = SettingsViewModel()
        let settingsView = SettingsView(viewModel: settingsViewModel)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()

        // 先设置窗口层级，再显示到前面
        window.level = .floating
        window.makeKeyAndOrderFront(nil)

        // 设置窗口不属于主应用窗口
        window.isReleasedWhenClosed = false

        // 使用 delegate 处理窗口关闭
        window.delegate = self
        settingsWindow = window
    }

    // MARK: - NSWindowDelegate
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == settingsWindow {
            // 隐藏窗口而不是关闭，防止应用退出
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window == settingsWindow {
                settingsWindow = nil
            } else if window == aboutWindow {
                aboutWindow = nil
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
