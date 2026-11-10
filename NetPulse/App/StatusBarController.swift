import AppKit
import CoreText
import Combine

/// 状态栏控制器：只消费 StatusBarSnapshot，不做二次采样
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private var statusLabelView: StatusBarCenteredLabelView?
    /// 图标+文字模式左侧的彩色 AppIcon（非 template）
    private var iconImageView: NSImageView?
    private var cancellables = Set<AnyCancellable>()
    private var lastAppliedSnapshot: StatusBarSnapshot?
    private weak var clickTarget: AnyObject?
    private var clickAction: Selector?
    private let iconTextGap: CGFloat = 3

    var button: NSStatusBarButton? { statusItem?.button }

    func install(target: AnyObject, action: Selector) {
        clickTarget = target
        clickAction = action
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        let iconView = NSImageView(frame: .zero)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
        iconView.wantsLayer = true
        iconView.isHidden = true
        button.addSubview(iconView)
        iconImageView = iconView

        let label = StatusBarCenteredLabelView(frame: .zero)
        label.autoresizingMask = [.width, .height]
        button.addSubview(label)
        statusLabelView = label

        button.target = target
        button.action = action
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// 订阅统一快照；相同内容节流跳过绘制
    func bind(snapshotPublisher: AnyPublisher<StatusBarSnapshot, Never>) {
        snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in
                self?.apply(snap)
            }
            .store(in: &cancellables)
    }

    func apply(_ snap: StatusBarSnapshot) {
        guard snap != lastAppliedSnapshot else { return }
        lastAppliedSnapshot = snap
        guard let button = statusItem?.button else { return }

        let downColor = StatusBarPalette.download
        let upColor = StatusBarPalette.upload
        let cpuColor = StatusBarPalette.usageColor(for: snap.cpuPercent)
        let memColor = StatusBarPalette.usageColor(for: snap.memPercent)
        let diskColor = snap.diskAvailable
            ? StatusBarPalette.usageColor(for: snap.diskPercent)
            : StatusBarPalette.usageDefault
        let tempColor = StatusBarPalette.temperatureColor(for: snap.cpuTemperatureCelsius)
        let tempText = snap.cpuTemperatureText

        button.attributedTitle = NSAttributedString(string: "")
        button.title = ""

        switch snap.displayMode {
        case .iconOnly:
            applyIconOnly(on: button)
        case .iconAndSpeed:
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
            let attr = NSMutableAttributedString(string: "↓\(snap.downloadSpeedText)", attributes: [
                .font: font,
                .foregroundColor: downColor
            ])
            appendTrailingTemperature(attr, text: tempText, color: tempColor, font: font)
            applyIconAndCenteredStatusText(attr, on: button)
        case .iconWithCPU:
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
            let attr = NSMutableAttributedString(string: "CPU \(snap.cpuText)", attributes: [
                .font: font,
                .foregroundColor: cpuColor
            ])
            appendTrailingTemperature(attr, text: tempText, color: tempColor, font: font)
            applyIconAndCenteredStatusText(attr, on: button)
        case .iconAndDualSpeed:
            applyIconAndCenteredStatusText(
                createDualSpeedText(
                    down: snap.downloadSpeedText, up: snap.uploadSpeedText,
                    downColor: downColor, upColor: upColor,
                    temp: tempText, tempColor: tempColor
                ),
                on: button
            )
        case .iconAndSystem:
            // 「网速 + 系统」不带左侧图标，仅 CT 文字
            let dual = createFixedWidthSpeedText(
                down: snap.downloadSpeedText, up: snap.uploadSpeedText,
                cpu: snap.cpuText, memory: snap.memText, disk: snap.diskText,
                temp: tempText,
                downColor: downColor, upColor: upColor,
                cpuColor: cpuColor, memColor: memColor, diskColor: diskColor,
                tempColor: tempColor
            )
            applyCenteredStatusText(dual.text, on: button, minWidth: dual.minWidth)
        }
    }

    func showContextMenu(_ menu: NSMenu) {
        statusItem?.menu = menu
        if let button = statusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        }
        statusItem?.menu = nil
    }

    // MARK: - 绘制辅助（保留 CT 防串色与 seal）

    /// 彩色程序图标（AppIcon），禁止 template，避免菜单栏发白/发黑
    private func menuBarAppIcon() -> NSImage {
        NetPulseAppIcon.menuBarImage()
    }

    private func clearButtonChrome(_ button: NSStatusBarButton) {
        button.image = nil
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
    }

    /// 仅图标：显示彩色 AppIcon
    private func applyIconOnly(on button: NSStatusBarButton) {
        clearButtonChrome(button)
        statusLabelView?.isHidden = true
        statusLabelView?.attributedText = NSAttributedString(string: "")
        iconImageView?.isHidden = true
        iconImageView?.image = nil

        let icon = menuBarAppIcon()
        button.image = icon
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        statusItem?.length = Constants.UI.menuBarIconSize + 6
    }

    /// 图标 + CT 文字：左侧彩色 AppIcon，右侧保留防串色文字
    private func applyIconAndCenteredStatusText(_ attr: NSAttributedString, on button: NSStatusBarButton) {
        clearButtonChrome(button)
        let icon = menuBarAppIcon()
        let iconSize = Constants.UI.menuBarIconSize
        let barH = button.bounds.height > 1 ? button.bounds.height : NSStatusBar.system.thickness

        guard let label = statusLabelView else {
            let textImg = makeCenteredStatusImage(from: attr)
            let totalW = iconSize + iconTextGap + textImg.size.width
            let composed = NSImage(size: NSSize(width: totalW, height: barH))
            composed.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            let iconY = (barH - iconSize) / 2
            icon.draw(in: NSRect(x: 0, y: iconY, width: iconSize, height: iconSize), from: .zero, operation: .sourceOver, fraction: 1.0)
            textImg.draw(
                in: NSRect(x: iconSize + iconTextGap, y: 0, width: textImg.size.width, height: barH),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
            composed.unlockFocus()
            composed.isTemplate = false
            button.image = composed
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            statusItem?.length = totalW
            return
        }

        if let iconView = iconImageView {
            iconView.isHidden = false
            iconView.image = icon
            let iconY = max((barH - iconSize) / 2, 0)
            iconView.frame = NSRect(x: 0, y: iconY, width: iconSize, height: iconSize)
        }

        label.isHidden = false
        label.attributedText = attr
        let textSize = label.intrinsicContentSize
        label.frame = NSRect(x: iconSize + iconTextGap, y: 0, width: textSize.width, height: barH)
        statusItem?.length = iconSize + iconTextGap + textSize.width
        label.needsDisplay = true
    }

    private func applyCenteredStatusText(_ attr: NSAttributedString, on button: NSStatusBarButton, minWidth: CGFloat = 0) {
        clearButtonChrome(button)
        iconImageView?.isHidden = true
        iconImageView?.image = nil

        guard let label = statusLabelView else {
            button.image = makeCenteredStatusImage(from: attr, minWidth: minWidth)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            statusItem?.length = NSStatusItem.variableLength
            return
        }
        label.isHidden = false
        label.attributedText = attr
        let size = label.intrinsicContentSize
        let barH = button.bounds.height > 1 ? button.bounds.height : NSStatusBar.system.thickness
        // 与 StatusBarCenteredLabelView.horizontalPadding 一致：左右各 2pt，并用 minWidth 撑住 TEMP 列右边缘
        let width = max(size.width, ceil(minWidth) + 4)
        label.frame = NSRect(x: 0, y: 0, width: width, height: barH)
        statusItem?.length = width
        label.needsDisplay = true
    }

    private func makeCenteredStatusImage(from attr: NSAttributedString, minWidth: CGFloat = 0) -> NSImage {
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
        let width = max(ceil(suggest.width) + pad * 2, ceil(minWidth) + pad * 2, 12)
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
        para.lineHeightMultiple = 0.85
        para.lineSpacing = 0
        if let tabStops {
            para.tabStops = tabStops
        }
        return para
    }

    private func appendTrailingTemperature(_ text: NSMutableAttributedString, text value: String, color: NSColor, font: NSFont, paragraphStyle: NSParagraphStyle? = nil) {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        if let paragraphStyle {
            attrs[.paragraphStyle] = paragraphStyle
        }
        text.append(NSAttributedString(string: "  \(value)", attributes: attrs))
    }

    private func createDualSpeedText(down: String, up: String, downColor: NSColor, upColor: NSColor, temp: String, tempColor: NSColor) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        let para = makeStatusBarParagraphStyle()

        let result = NSMutableAttributedString()
        let upAttr = NSMutableAttributedString(string: "↑\(up)", attributes: [
            .font: font,
            .paragraphStyle: para
        ])
        upAttr.addAttribute(.foregroundColor, value: upColor, range: NSRange(location: 0, length: upAttr.length))
        result.append(upAttr)
        appendTrailingTemperature(result, text: temp, color: tempColor, font: font, paragraphStyle: para)
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: font,
            .paragraphStyle: para
        ]))
        let downAttr = NSMutableAttributedString(string: "↓\(down)", attributes: [
            .font: font,
            .paragraphStyle: para
        ])
        downAttr.addAttribute(.foregroundColor, value: downColor, range: NSRange(location: 0, length: downAttr.length))
        result.append(downAttr)
        sealMenuBarSpeedColors(result, upColor: upColor, downColor: downColor)
        return result
    }

    private func createFixedWidthSpeedText(
        down: String, up: String, cpu: String, memory: String, disk: String,
        temp: String,
        downColor: NSColor, upColor: NSColor,
        cpuColor: NSColor, memColor: NSColor, diskColor: NSColor,
        tempColor: NSColor
    ) -> (text: NSAttributedString, minWidth: CGFloat) {
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        let labelFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)

        // 四列（CPU / MEM / SSD / TEMP）统一按「TEMP」在标签字体下的宽度排，略加内边距；
        // 同时保证上行占用/温度数值放得下。列左边缘对齐；标签与数值在同宽槽位内水平居中。
        let columnPadding: CGFloat = 3
        let tempLabelWidth = statusBarTextWidth("TEMP", font: labelFont)
        let maxValueWidth = [
            cpu, memory, disk, temp, "100%", "--°"
        ].map { statusBarTextWidth($0, font: font) }.max() ?? tempLabelWidth
        let columnWidth = max(tempLabelWidth, maxValueWidth) + columnPadding * 2
        let speedGap: CGFloat = 6
        let speedWidth = max(
            statusBarTextWidth("↑\(up)", font: font),
            statusBarTextWidth("↓\(down)", font: font),
            40
        ) + speedGap
        let columnCenters: [CGFloat] = (0..<4).map { speedWidth + columnWidth * (CGFloat($0) + 0.5) }
        let totalWidth = speedWidth + columnWidth * 4

        // 只用四列中心制表位。不要再在行尾追加 \t + 零宽字符去撑宽度：
        // 2.0.48 那样做会让 Core Text 把垫宽字符折成空行，两行中间多出一块空白。
        // 列右边缘改由调用方按 totalWidth 设置视图最小宽度来保证，避免裁切 TEMP。
        let para = makeStatusBarParagraphStyle(tabStops: [
            NSTextTab(textAlignment: .center, location: columnCenters[0]),
            NSTextTab(textAlignment: .center, location: columnCenters[1]),
            NSTextTab(textAlignment: .center, location: columnCenters[2]),
            NSTextTab(textAlignment: .center, location: columnCenters[3])
        ])

        let secondary = NSColor.secondaryLabelColor
        let primary = NSColor.textColor

        let result = NSMutableAttributedString()

        let line1Base: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: primary,
            .paragraphStyle: para
        ]
        let upAttr = NSMutableAttributedString(string: "↑\(up)", attributes: line1Base)
        upAttr.addAttribute(.foregroundColor, value: upColor, range: NSRange(location: 0, length: upAttr.length))
        result.append(upAttr)

        let tabAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: primary,
            .paragraphStyle: para
        ]
        result.append(NSAttributedString(string: "\t", attributes: tabAttrs))
        result.append(NSAttributedString(string: cpu, attributes: [
            .font: font,
            .foregroundColor: cpuColor,
            .paragraphStyle: para
        ]))
        result.append(NSAttributedString(string: "\t", attributes: tabAttrs))
        result.append(NSAttributedString(string: memory, attributes: [
            .font: font,
            .foregroundColor: memColor,
            .paragraphStyle: para
        ]))
        result.append(NSAttributedString(string: "\t", attributes: tabAttrs))
        result.append(NSAttributedString(string: disk, attributes: [
            .font: font,
            .foregroundColor: diskColor,
            .paragraphStyle: para
        ]))
        result.append(NSAttributedString(string: "\t", attributes: tabAttrs))
        result.append(NSAttributedString(string: temp, attributes: [
            .font: font,
            .foregroundColor: tempColor,
            .paragraphStyle: para
        ]))
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: font,
            .paragraphStyle: para
        ]))

        let downAttr = NSMutableAttributedString(string: "↓\(down)", attributes: [
            .font: font,
            .paragraphStyle: para
        ])
        downAttr.addAttribute(.foregroundColor, value: downColor, range: NSRange(location: 0, length: downAttr.length))
        result.append(downAttr)
        result.append(NSAttributedString(string: "\tCPU\tMEM\tSSD\tTEMP", attributes: [
            .font: labelFont,
            .foregroundColor: secondary,
            .paragraphStyle: para
        ]))

        sealMenuBarSpeedColors(result, upColor: upColor, downColor: downColor)
        return (result, totalWidth)
    }


    private func statusBarTextWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func sealMenuBarSpeedColors(_ text: NSMutableAttributedString, upColor: NSColor, downColor: NSColor) {
        let full = text.string
        let ns = full as NSString
        func seal(prefix: Character, color: NSColor) {
            guard let idx = full.firstIndex(of: prefix) else { return }
            let start = full.distance(from: full.startIndex, to: idx)
            var end = start + 1
            while end < ns.length {
                let ch = ns.character(at: end)
                if ch == 9 || ch == 10 { break }
                end += 1
            }
            if end > start {
                text.addAttribute(.foregroundColor, value: color, range: NSRange(location: start, length: end - start))
            }
        }
        seal(prefix: "↑", color: upColor)
        seal(prefix: "↓", color: downColor)
    }
}
