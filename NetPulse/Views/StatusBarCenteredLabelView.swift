import AppKit
import CoreText

/// 状态栏文字视图：用 CoreText 真实字形墨迹高度在画布内垂直居中。
/// 禁止使用 NSString.boundingRect + usesFontLeading 估高（会把行高估高导致墨迹视觉偏上）。
final class StatusBarCenteredLabelView: NSView {
    var attributedText: NSAttributedString = NSAttributedString() {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private let horizontalPadding: CGFloat = 2
    /// 光学补偿：墨迹几何居中后整体下移（pt），抵消菜单栏视觉偏上感
    private let opticalNudgeDown: CGFloat = 1.5

    override var intrinsicContentSize: NSSize {
        let barH = NSStatusBar.system.thickness
        guard attributedText.length > 0 else {
            return NSSize(width: 18, height: barH)
        }
        let ctAttr = Self.makeCTAttributedString(from: attributedText)
        let size = Self.suggestTypographicSize(for: ctAttr, constrainedWidth: 4000)
        return NSSize(width: ceil(size.width) + horizontalPadding * 2, height: barH)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard attributedText.length > 0 else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let canvasH = bounds.height > 1 ? bounds.height : NSStatusBar.system.thickness
        let maxW = max(bounds.width - horizontalPadding * 2, 1)

        let ctAttr = Self.makeCTAttributedString(from: attributedText)
        let framesetter = CTFramesetterCreateWithAttributedString(ctAttr)

        var fitRange = CFRange(location: 0, length: 0)
        let suggest = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: maxW, height: CGFloat.greatestFiniteMagnitude),
            &fitRange
        )
        let layoutH = max(ceil(suggest.height), 1)
        let layoutW = maxW

        // 在本地布局坐标（path 原点 0,0）测真实墨迹
        let measurePath = CGPath(
            rect: CGRect(x: 0, y: 0, width: layoutW, height: layoutH),
            transform: nil
        )
        let measureFrame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            measurePath,
            nil
        )
        let ink = Self.unionImageBounds(of: measureFrame)

        let inkMidY: CGFloat
        if ink.isNull || ink.height < 0.5 {
            inkMidY = layoutH / 2.0
        } else {
            inkMidY = ink.midY
        }

        // 墨迹几何中心对齐画布中心，再整体下移光学补偿（非 flipped：y 向上，下移即减小 y）
        let targetInkMidY = canvasH / 2.0 - opticalNudgeDown
        let pathOriginY = targetInkMidY - inkMidY
        let pathOriginX = horizontalPadding

        context.saveGState()
        context.textMatrix = .identity
        let drawPath = CGPath(
            rect: CGRect(x: pathOriginX, y: pathOriginY, width: layoutW, height: layoutH),
            transform: nil
        )
        let drawFrame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            drawPath,
            nil
        )
        CTFrameDraw(drawFrame, context)
        context.restoreGState()
    }

    /// 点击穿透到 NSStatusBarButton，保留原有左右键逻辑
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    // MARK: - CoreText helpers

    /// 将 AppKit 属性转为 CoreText 可绘制属性（NSColor → CGColor）。
    static func makeCTAttributedString(from attr: NSAttributedString) -> CFAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attr)
        let full = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            if let color = attrs[.foregroundColor] as? NSColor {
                mutable.removeAttribute(.foregroundColor, range: range)
                let cg = color.cgColor
                mutable.addAttribute(
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String),
                    value: cg,
                    range: range
                )
            }
        }
        return mutable as CFAttributedString
    }

    static func suggestTypographicSize(
        for ctAttr: CFAttributedString,
        constrainedWidth: CGFloat
    ) -> CGSize {
        let framesetter = CTFramesetterCreateWithAttributedString(ctAttr)
        var fitRange = CFRange(location: 0, length: 0)
        return CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: constrainedWidth, height: CGFloat.greatestFiniteMagnitude),
            &fitRange
        )
    }

    /// 合并各 CTLine 的 CTLineGetImageBounds，得到真实字形墨迹包围盒（相对 frame path 原点）。
    static func unionImageBounds(of frame: CTFrame) -> CGRect {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        guard !lines.isEmpty else { return .null }

        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        var unionRect = CGRect.null
        for (i, line) in lines.enumerated() {
            // nil context：相对该行 baseline 原点的墨迹盒
            let imageBounds = CTLineGetImageBounds(line, nil)
            guard !imageBounds.isNull, imageBounds.width > 0 || imageBounds.height > 0 else { continue }
            let origin = origins[i]
            let lineInk = imageBounds.offsetBy(dx: origin.x, dy: origin.y)
            unionRect = unionRect.union(lineInk)
        }
        return unionRect
    }
}
