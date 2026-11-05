import AppKit
import CoreText
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // MARK: - 属性
    private var statusItem: NSStatusItem?
    private var statusLabelView: StatusBarCenteredLabelView?
    private var popover: NSPopover?
    private var viewModel: NetworkMonitorViewModel!
    private var networkService: NetworkMonitorService!
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private var aboutWindow: NSWindow?
    private var settingsWindow: NSWindow?

    // MARK: - 应用代理方法
    func applicationDidFinishLaunching(_ notification: Notification) {
        let existingApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        if existingApps.count > 1 {
            print("[NetPulse] 已有实例在运行，退出")
            NSApp.terminate(nil)
            return
        }

        setupServices()
        setupStatusItem()
        setupPopover()
        startMonitoring()
        // 不再在启动时挂全局鼠标 monitor；popover 显示时再挂
        setupSleepWakeHandling()

        if ProcessInfo.processInfo.arguments.contains("--show-about") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showAbout()
            }
        }
    }

    private func setupSleepWakeHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemWillSleep() {
        if let popover = self.popover, popover.isShown {
            popover.performClose(nil)
        }
        removeEventMonitor()
        networkService?.pauseForSleep()
    }

    @objc private func systemDidWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.networkService?.resumeAfterWake()
            if let popover = self.popover, popover.isShown {
                popover.contentViewController?.view.window?.makeKey()
            }
            if let btn = self.statusItem?.button {
                self.updateButton(btn)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stopMonitoring()
        StorageService.shared.saveTodayTraffic()
        removeEventMonitor()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if let popover = self.popover, popover.isShown {
            popover.contentViewController?.view.window?.makeKey()
        }
    }

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

        if settings.launchAtLogin {
            LoginItemService.shared.enable()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        // 自定义居中文字视图（按 bounds 垂直居中绘制）
        let label = StatusBarCenteredLabelView(frame: .zero)
        label.autoresizingMask = [.width, .height]
        button.addSubview(label)
        statusLabelView = label

        updateButton(button)

        // 合并状态栏刷新：多个 Published 合成一次 updateButton，避免同拍重复绘制
        viewModel.$menuBarIcon
            .combineLatest(
                viewModel.$menuBarSpeedText,
                viewModel.$menuBarUploadSpeedText,
                viewModel.$menuBarDualSpeedText
            )
            .combineLatest(viewModel.$menuBarDisplayMode, viewModel.$cpuUsageText)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                guard let btn = self?.statusItem?.button else { return }
                self?.updateButton(btn)
            }
            .store(in: &cancellables)

        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: Constants.UI.panelWidth, height: 645)
        popover?.behavior = .transient
        popover?.animates = true

        let contentView = DropdownPanelView(viewModel: viewModel)
        popover?.contentViewController = NSHostingController(rootView: contentView)

        NotificationCenter.default.addObserver(
            forName: .openSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showSettings()
        }

        NotificationCenter.default.addObserver(
            forName: .openAbout,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showAbout()
        }

        NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.viewModel.updateSettings()
            if let btn = self?.statusItem?.button {
                self?.updateButton(btn)
            }
        }
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
                self?.removeEventMonitor()
            }
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func menuBarAppIcon() -> NSImage {
        let size = Constants.UI.menuBarIconSize
        let source = NSApp.applicationIconImage
            ?? NSImage(named: NSImage.applicationIconName)
            ?? NSImage(size: NSSize(width: size, height: size))
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    private func updateButton(_ button: NSStatusBarButton) {
        let mode = viewModel.menuBarDisplayMode
        let downSpeed = viewModel.menuBarSpeedText
        let upSpeed = viewModel.menuBarUploadSpeedText
        let cpuUsage = CPUMonitorService.shared.getFormattedCPUUsage()
        let memoryUsage = MemoryMonitorService.shared.getFormattedMemoryUsage()
        let diskUsage = DiskMonitorService.shared.getFormattedDiskUsage()

        let downColor = NSColor(hex: "34C759") // netPulseGreen
        let upColor = NSColor(hex: "007AFF")   // netPulseBlue

        // 清空 button 原生 title，改由自定义视图 / image 绘制，避免 attributedTitle 偏上
        button.attributedTitle = NSAttributedString(string: "")
        button.title = ""

        switch mode {
        case .iconOnly:
            statusLabelView?.isHidden = true
            statusLabelView?.attributedText = NSAttributedString(string: "")
            button.image = menuBarAppIcon()
            button.imagePosition = .imageOnly
            statusItem?.length = NSStatusItem.variableLength
        case .iconAndSpeed:
            button.image = nil
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
            let attr = NSAttributedString(string: "↓\(downSpeed)", attributes: [
                .font: font,
                .foregroundColor: downColor
            ])
            applyCenteredStatusText(attr, on: button)
        case .iconWithCPU:
            button.image = nil
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
            let attr = NSAttributedString(string: "CPU \(cpuUsage)", attributes: [
                .font: font,
                .foregroundColor: NSColor.textColor
            ])
            applyCenteredStatusText(attr, on: button)
        case .iconAndDualSpeed:
            button.image = nil
            applyCenteredStatusText(
                createDualSpeedText(down: downSpeed, up: upSpeed, downColor: downColor, upColor: upColor),
                on: button
            )
        case .iconAndSystem:
            button.image = nil
            applyCenteredStatusText(
                createFixedWidthSpeedText(
                    down: downSpeed, up: upSpeed, cpu: cpuUsage, memory: memoryUsage, disk: diskUsage,
                    downColor: downColor, upColor: upColor
                ),
                on: button
            )
        }
    }

    /// 将 attributed 文字交给 StatusBarCenteredLabelView，按 status bar 高度垂直居中绘制。
    private func applyCenteredStatusText(_ attr: NSAttributedString, on button: NSStatusBarButton) {
        guard let label = statusLabelView else {
            // 兜底：离屏 image 垂直居中（同方案）
            button.image = makeCenteredStatusImage(from: attr)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            statusItem?.length = NSStatusItem.variableLength
            return
        }
        label.isHidden = false
        label.attributedText = attr
        let size = label.intrinsicContentSize
        let barH = button.bounds.height > 1 ? button.bounds.height : NSStatusBar.system.thickness
        label.frame = NSRect(x: 0, y: 0, width: size.width, height: barH)
        statusItem?.length = size.width
        label.needsDisplay = true
    }

    /// 离屏绘制：CoreText 墨迹垂直居中（备用 / 兜底），与 StatusBarCenteredLabelView 同策略。
    private func makeCenteredStatusImage(from attr: NSAttributedString) -> NSImage {
        let barH = NSStatusBar.system.thickness
        let opticalNudgeDown: CGFloat = 1.5
        let pad: CGFloat = 2

        let ctAttr = StatusBarCenteredLabelView.makeCTAttributedString(from: attr)
        let framesetter = CTFramesetterCreateWithAttributedString(ctAttr)
        var fitRange = CFRange(location: 0, length: 0)
        let suggest = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: 4000, height: CGFloat.greatestFiniteMagnitude),
            &fitRange
        )
        let width = max(ceil(suggest.width) + pad * 2, 12)
        let layoutH = max(ceil(suggest.height), 1)
        let layoutW = max(width - pad * 2, 1)

        let measurePath = CGPath(rect: CGRect(x: 0, y: 0, width: layoutW, height: layoutH), transform: nil)
        let measureFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), measurePath, nil)
        let ink = StatusBarCenteredLabelView.unionImageBounds(of: measureFrame)
        let inkMidY: CGFloat = (ink.isNull || ink.height < 0.5) ? (layoutH / 2.0) : ink.midY
        let targetInkMidY = barH / 2.0 - opticalNudgeDown
        let pathOriginY = targetInkMidY - inkMidY

        let size = NSSize(width: width, height: barH)
        let image = NSImage(size: size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.textMatrix = .identity
            let drawPath = CGPath(
                rect: CGRect(x: pad, y: pathOriginY, width: layoutW, height: layoutH),
                transform: nil
            )
            let drawFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), drawPath, nil)
            CTFrameDraw(drawFrame, ctx)
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func makeStatusBarParagraphStyle(tabStops: [NSTextTab]? = nil) -> NSMutableParagraphStyle {
        let para = NSMutableParagraphStyle()
        para.alignment = .left
        // 紧凑行距；不再用过紧的 max/min line height（易导致视觉偏上）
        para.lineHeightMultiple = 0.85
        para.lineSpacing = 0
        if let tabStops {
            para.tabStops = tabStops
        }
        return para
    }

    private func createDualSpeedText(down: String, up: String, downColor: NSColor, upColor: NSColor) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        let para = makeStatusBarParagraphStyle()

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "↑\(up)", attributes: [
            .font: font,
            .foregroundColor: upColor,
            .paragraphStyle: para
        ]))
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: font,
            .paragraphStyle: para
        ]))
        result.append(NSAttributedString(string: "↓\(down)", attributes: [
            .font: font,
            .foregroundColor: downColor,
            .paragraphStyle: para
        ]))
        return result
    }

    // 两行：左侧上下速度（着色），右侧 CPU / MEM / SSD 标签；整块由自定义视图垂直居中
    private func createFixedWidthSpeedText(
        down: String, up: String, cpu: String, memory: String, disk: String,
        downColor: NSColor, upColor: NSColor
    ) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        let labelFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)

        let speedWidth: CGFloat = 40
        let cpuWidth: CGFloat = 26
        let memWidth: CGFloat = 26

        let spacing1: CGFloat = 28
        let spacing2: CGFloat = 14
        let spacing3: CGFloat = 18

        let para = makeStatusBarParagraphStyle(tabStops: [
            NSTextTab(textAlignment: .right, location: speedWidth),
            NSTextTab(textAlignment: .right, location: speedWidth + spacing1 + cpuWidth),
            NSTextTab(textAlignment: .right, location: speedWidth + spacing1 + cpuWidth + spacing2 + memWidth),
            NSTextTab(textAlignment: .left, location: speedWidth + spacing1 + cpuWidth + spacing2 + memWidth + spacing3)
        ])

        let secondary = NSColor.secondaryLabelColor
        let primary = NSColor.textColor

        let result = NSMutableAttributedString()

        // Line 1: ↑up \t cpuVal \t memVal \t diskVal
        let line1Base: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: primary,
            .paragraphStyle: para
        ]
        let upAttr = NSMutableAttributedString(string: "↑\(up)", attributes: line1Base)
        upAttr.addAttribute(.foregroundColor, value: upColor, range: NSRange(location: 0, length: upAttr.length))
        result.append(upAttr)
        result.append(NSAttributedString(string: "\t\(cpu)\t\(memory)\t\(disk)", attributes: line1Base))
        result.append(NSAttributedString(string: "\n", attributes: line1Base))

        // Line 2: ↓down \t CPU \t MEM \t SSD
        let downAttr = NSMutableAttributedString(string: "↓\(down)", attributes: [
            .font: font,
            .foregroundColor: downColor,
            .paragraphStyle: para
        ])
        result.append(downAttr)
        let labels = NSAttributedString(string: "\tCPU\tMEM\tSSD", attributes: [
            .font: labelFont,
            .foregroundColor: secondary,
            .paragraphStyle: para
        ])
        result.append(labels)

        return result
    }

    private func startMonitoring() {
        NotificationService.shared.requestAuthorization()
        viewModel.startMonitoring()
    }

    // MARK: - 按钮点击事件
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        print("[NetPulse] 按钮被点击!")
        guard let event = NSApp.currentEvent else {
            print("[NetPulse] 无法获取事件，默认左键行为")
            togglePopover()
            return
        }

        print("[NetPulse] 事件类型: \(event.type)")
        if event.type == .rightMouseUp {
            print("[NetPulse] 显示右键菜单")
            showMenu()
        } else {
            print("[NetPulse] 切换面板")
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
        print("[NetPulse] togglePopover 被调用")
        guard let button = statusItem?.button else {
            print("[NetPulse] button 不存在")
            return
        }

        if popover?.isShown == true {
            print("[NetPulse] 关闭弹窗")
            popover?.performClose(nil)
            removeEventMonitor()
        } else {
            print("[NetPulse] 显示弹窗")
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover?.contentViewController?.view.window?.makeKey()
            installEventMonitor()
        }
    }

    @objc private func showAbout() {
        if let existing = aboutWindow {
            configureAboutWindowAlwaysOnTop(existing)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

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
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: aboutView)
        window.center()

        configureAboutWindowAlwaysOnTop(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window.delegate = self
        aboutWindow = window
    }

    private func configureAboutWindowAlwaysOnTop(_ window: NSWindow) {
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
    }

    @objc private func showSettings() {
        if settingsWindow != nil {
            settingsWindow?.makeKeyAndOrderFront(nil)
            return
        }

        let settingsViewModel = SettingsViewModel()
        let settingsView = SettingsView(viewModel: settingsViewModel)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()

        window.level = .floating
        window.makeKeyAndOrderFront(nil)

        window.isReleasedWhenClosed = false

        window.delegate = self
        settingsWindow = window
    }

    // MARK: - NSWindowDelegate
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == settingsWindow {
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
