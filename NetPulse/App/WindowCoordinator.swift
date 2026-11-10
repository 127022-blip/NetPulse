import AppKit
import SwiftUI
import Combine

/// 关于 / 设置窗口协调
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private var aboutWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        NotificationCenter.default.publisher(for: .settingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshOpenWindowAppearances()
            }
            .store(in: &cancellables)
    }

    func showAbout() {
        if let existing = aboutWindow {
            configureUtilityWindow(existing)
            configureAboutWindowChrome(existing)
            applyWindowAppearance(existing)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aw = Constants.UI.aboutWindowWidth
        let ah = Constants.UI.aboutWindowHeight
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: aw, height: ah),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configureAboutWindowChrome(window)
        window.isMovableByWindowBackground = true
        let aboutView = AboutView { [weak self] in
            self?.closeAbout()
        }
        window.contentView = NSHostingView(rootView: aboutView)
        window.setContentSize(NSSize(width: aw, height: ah))
        window.center()
        configureUtilityWindow(window)
        applyWindowAppearance(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window.delegate = self
        aboutWindow = window
    }

    /// 通过协调器持有的 aboutWindow 关闭，不按标题查找、不回退 keyWindow
    func closeAbout() {
        aboutWindow?.performClose(nil)
    }

    /// 隐藏标题、标题栏透明，保留关闭交通灯
    private func configureAboutWindowChrome(_ window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    func showSettings() {
        if let existing = settingsWindow {
            configureUtilityWindow(existing)
            applySettingsWindowSizing(existing)
            applyWindowAppearance(existing)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsViewModel = SettingsViewModel()
        let settingsView = SettingsView(viewModel: settingsViewModel)

        let w = Constants.UI.settingsWindowWidth
        let h = Constants.UI.settingsWindowHeight
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        applySettingsWindowSizing(window)
        configureUtilityWindow(window)
        applyWindowAppearance(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.delegate = self
        settingsWindow = window
    }


    /// 关于窗 / 设置窗跟随共用主题
    private func applyWindowAppearance(_ window: NSWindow) {
        window.appearance = AppearancePreference.shared.nsAppearance
    }

    private func refreshOpenWindowAppearances() {
        if let window = aboutWindow {
            applyWindowAppearance(window)
        }
        if let window = settingsWindow {
            applyWindowAppearance(window)
        }
    }

    /// 关于窗 / 设置窗统一的工具窗配置
    private func configureUtilityWindow(_ window: NSWindow) {
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
    }

    /// 设置窗尺寸单一真相源：固定宽度，允许垂直缩放
    private func applySettingsWindowSizing(_ window: NSWindow) {
        let w = Constants.UI.settingsWindowWidth
        window.minSize = NSSize(width: w, height: Constants.UI.settingsWindowMinHeight)
        window.maxSize = NSSize(width: w, height: Constants.UI.settingsWindowMaxHeight)
        var frame = window.frame
        frame.size.width = w
        if frame.size.height < Constants.UI.settingsWindowMinHeight {
            frame.size.height = Constants.UI.settingsWindowMinHeight
        }
        if frame.size.height > Constants.UI.settingsWindowMaxHeight {
            frame.size.height = Constants.UI.settingsWindowMaxHeight
        }
        window.setFrame(frame, display: false)
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
}
