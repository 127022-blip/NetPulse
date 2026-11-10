import AppKit
import CoreText

/// 状态栏文字视图：CoreText 墨迹垂直居中；CT attributed / framesetter 缓存，文本变化才失效
final class StatusBarCenteredLabelView: NSView {
    var attributedText: NSAttributedString = NSAttributedString() {
        didSet {
            if oldValue != attributedText {
                invalidateCTCache()
            }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private let horizontalPadding: CGFloat = 2
    private let opticalNudgeDown: CGFloat = 1.5

    // CT 缓存
    private var cachedCTAttr: CFAttributedString?
    private var cachedFramesetter: CTFramesetter?
    private var cachedSourceHash: Int = 0

    override var intrinsicContentSize: NSSize {
        let barH = NSStatusBar.system.thickness
        guard attributedText.length > 0 else {
            return NSSize(width: 18, height: barH)
        }
        let ctAttr = cachedOrMakeCTAttributedString()
        let size = Self.suggestTypographicSize(for: ctAttr, constrainedWidth: 4000)
        return NSSize(width: ceil(size.width) + horizontalPadding * 2, height: barH)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard attributedText.length > 0 else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let canvasH = bounds.height > 1 ? bounds.height : NSStatusBar.system.thickness
        let maxW = max(bounds.width - horizontalPadding * 2, 1)

        let ctAttr = cachedOrMakeCTAttributedString()
        let framesetter = cachedOrMakeFramesetter(for: ctAttr)

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

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - CT cache

    private func invalidateCTCache() {
        cachedCTAttr = nil
        cachedFramesetter = nil
        cachedSourceHash = 0
    }

    private func cachedOrMakeCTAttributedString() -> CFAttributedString {
        let hash = attributedText.string.hashValue ^ attributedText.length
        if let cached = cachedCTAttr, hash == cachedSourceHash {
            return cached
        }
        let made = Self.makeCTAttributedString(from: attributedText)
        cachedCTAttr = made
        cachedFramesetter = nil
        cachedSourceHash = hash
        return made
    }

    private func cachedOrMakeFramesetter(for ctAttr: CFAttributedString) -> CTFramesetter {
        if let fs = cachedFramesetter {
            return fs
        }
        let fs = CTFramesetterCreateWithAttributedString(ctAttr)
        cachedFramesetter = fs
        return fs
    }

    /// 先收集再写回，避免 enumerate 中原地修改导致相邻 run 串色
    static func makeCTAttributedString(from attr: NSAttributedString) -> CFAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attr)
        let full = NSRange(location: 0, length: mutable.length)
        var replacements: [(NSRange, CGColor)] = []
        mutable.enumerateAttribute(.foregroundColor, in: full, options: []) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let cg = color.usingColorSpace(.sRGB)?.cgColor ?? color.cgColor
            replacements.append((range, cg))
        }
        for (range, cg) in replacements {
            mutable.removeAttribute(.foregroundColor, range: range)
            mutable.addAttribute(
                NSAttributedString.Key(kCTForegroundColorAttributeName as String),
                value: cg,
                range: range
            )
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

    static func unionImageBounds(of frame: CTFrame) -> CGRect {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        guard !lines.isEmpty else { return .null }

        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        var unionRect = CGRect.null
        for (i, line) in lines.enumerated() {
            let imageBounds = CTLineGetImageBounds(line, nil)
            guard !imageBounds.isNull, imageBounds.width > 0 || imageBounds.height > 0 else { continue }
            let origin = origins[i]
            let lineInk = imageBounds.offsetBy(dx: origin.x, dy: origin.y)
            unionRect = unionRect.union(lineInk)
        }
        return unionRect
    }
}
