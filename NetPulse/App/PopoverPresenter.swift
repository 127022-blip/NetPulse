import AppKit
import SwiftUI

/// 弹窗展示：顶部固定锚定、紧贴状态栏项正下方、自适应高度、全局点击监听（左+右）与 Escape
final class PopoverPresenter: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var localKeyMonitor: Any?
    /// 当前锚定的状态栏按钮（高度变化时重新顶部对齐）
    private weak var anchorButton: NSStatusBarButton?

    var isShown: Bool { popover?.isShown == true }

    func setup(rootView: some View) {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.delegate = self

        let host = NSHostingController(rootView: rootView)
        pop.contentViewController = host

        // 先给合理宽度；高度用 fittingSize 自适应
        let fitting = host.view.fittingSize
        let width = Constants.UI.panelWidth
        let height = max(fitting.height, 320)
        pop.contentSize = NSSize(width: width, height: height)

        self.popover = pop
    }

    /// 内容变更后重测高度；若已显示则保持顶部固定（高度变大时 origin.y 下移）
    func refreshFittingSize() {
        guard let pop = popover, let host = pop.contentViewController else { return }
        host.view.layoutSubtreeIfNeeded()
        let fitting = host.view.fittingSize
        let height = max(fitting.height, 320)
        let newContentSize = NSSize(width: Constants.UI.panelWidth, height: height)

        if pop.isShown, let win = host.view.window {
            let topY = win.frame.maxY
            let midX = win.frame.midX
            let wasAnimating = pop.animates
            pop.animates = false
            pop.contentSize = newContentSize
            // contentSize 变更后窗口可能被 AppKit 挪位；强制顶部固定
            var frame = win.frame
            frame.origin.y = topY - frame.height
            frame.origin.x = midX - frame.width / 2
            if let screen = win.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.maxX - frame.width, visible.minX))
                frame.origin.y = max(frame.origin.y, visible.minY)
            }
            win.setFrame(frame, display: true)
            // 若仍有 anchorButton，再按 button 下沿校正一次顶部（更紧贴）
            if let button = anchorButton {
                PopoverAnchor.applyTopAnchor(to: win, relativeTo: button)
            }
            pop.animates = wasAnimating
        } else {
            pop.contentSize = newContentSize
        }
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover?.isShown == true {
            close()
        } else {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton) {
        anchorButton = button
        refreshFittingSize()
        let wasAnimating = popover?.animates ?? true
        popover?.animates = false
        // 先按系统方式弹出到 button 下方，再立刻改为顶部固定、紧贴正下方
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        PopoverAnchor.applyTopAnchor(
            to: popover?.contentViewController?.view.window,
            relativeTo: button
        )
        popover?.animates = wasAnimating
        popover?.contentViewController?.view.window?.makeKey()
        installEventMonitors()
    }

    func close() {
        popover?.performClose(nil)
        anchorButton = nil
        removeEventMonitors()
    }

    // MARK: - 监听

    private func installEventMonitors() {
        guard eventMonitor == nil else { return }
        // 左键 + 右键都能关闭
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.close()
                return nil
            }
            return event
        }
    }

    private func removeEventMonitors() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        anchorButton = nil
        removeEventMonitors()
    }
}
