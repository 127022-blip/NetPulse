import AppKit

/// 弹窗顶部固定锚定：顶部紧贴状态栏项下沿；内容增减时顶部不动、向下延展
enum PopoverAnchor {
    /// 与状态栏项之间的紧贴间隙（像素）
    static let tightGap: CGFloat = 1

    /// 将 button.bounds 转为屏幕坐标矩形
    static func buttonScreenRect(of button: NSStatusBarButton) -> NSRect? {
        guard let win = button.window else { return nil }
        let inWindow = button.convert(button.bounds, to: nil)
        return win.convertToScreen(inWindow)
    }

    /// 按「顶部固定 + 水平居中对齐状态栏项」计算窗口 frame（AppKit：origin 左下）
    /// - 顶部 = button 下沿 − tightGap（即 frame.maxY 固定在该处）
    /// - 水平 = 弹窗中心对齐 button 中心，再夹紧到 visibleFrame
    static func topAnchoredFrame(windowSize: NSSize, relativeTo button: NSStatusBarButton) -> NSRect {
        guard let buttonRect = buttonScreenRect(of: button) else {
            return NSRect(origin: .zero, size: windowSize)
        }

        // button 下沿（屏幕坐标 minY）正下方紧贴 → 弹窗顶部 maxY
        let topY = buttonRect.minY - tightGap
        var originX = buttonRect.midX - windowSize.width / 2
        var originY = topY - windowSize.height

        let screen = button.window?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: buttonRect.midX, y: buttonRect.midY)) })
            ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            // 水平夹紧
            originX = min(max(originX, visible.minX), max(visible.maxX - windowSize.width, visible.minX))
            // 底部不低于可见区；若被迫上移，顶部仍尽量靠近原 topY（溢出时不可避免）
            originY = max(originY, visible.minY)
            if originY + windowSize.height > visible.maxY {
                originY = max(visible.maxY - windowSize.height, visible.minY)
            }
        }

        return NSRect(x: originX, y: originY, width: windowSize.width, height: windowSize.height)
    }

    /// show 后立刻套用顶部锚定（关动画时调用，避免闪烁）
    static func applyTopAnchor(to window: NSWindow?, relativeTo button: NSStatusBarButton) {
        guard let win = window else { return }
        let frame = topAnchoredFrame(windowSize: win.frame.size, relativeTo: button)
        win.setFrame(frame, display: true)
    }

    /// 内容高度变化时保持顶部不变：新 origin.y = 旧 maxY − 新 height
    static func resizeKeepingTopFixed(window: NSWindow?, preservingTopY topY: CGFloat, newWindowSize: NSSize) {
        guard let win = window else { return }
        var frame = win.frame
        frame.size = newWindowSize
        frame.origin.y = topY - newWindowSize.height
        // 保持水平中心不变（相对旧 frame）
        let midX = win.frame.midX
        frame.origin.x = midX - newWindowSize.width / 2

        if let screen = win.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.maxX - newWindowSize.width, visible.minX))
            frame.origin.y = max(frame.origin.y, visible.minY)
        }
        win.setFrame(frame, display: true)
    }
}
