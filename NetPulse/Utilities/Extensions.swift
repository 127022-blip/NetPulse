import Foundation
import SwiftUI
import AppKit
import Combine

// MARK: - Color 扩展
extension Color {
    /// 已连接等状态色 #34C759（仅状态，不用于下载）
    static let netPulseGreen = Color(hex: "34C759")
    /// 下载品牌色 #00C7BE（与 StatusBarPalette.download 共用定义）
    static let netPulseDownload = Color(hex: "00C7BE")
    /// 上传品牌色 #007AFF（与 StatusBarPalette.upload 共用定义）
    static let netPulseUpload = Color(hex: "007AFF")
    static let netPulseBlue = Color(hex: "007AFF")
    static let netPulseOrange = Color(hex: "FF9500")
    /// 断开红 #FF3B30
    static let netPulseRed = Color(hex: "FF3B30")
    static let netPulseGray = Color(hex: "8E8E93")

    /// 占用色阶（沿用 StatusBarPalette：>50 黄 / >80 橙 / >90 红）
    static func usageColor(for percent: Double) -> Color {
        Color(nsColor: StatusBarPalette.usageColor(for: percent))
    }

    /// 温度数字颜色：与状态栏 / 弹窗 TEMP 同一套规则（读不到为次要灰）
    static func temperatureColor(for celsius: Double?) -> Color {
        Color(nsColor: StatusBarPalette.temperatureColor(for: celsius))
    }

    /// 从十六进制颜色值初始化（sRGB）
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View 扩展
extension View {
    /// 卡片：controlBackground + 圆角 12 + 0.5pt separator 描边（无大阴影，深色模式干净）
    func cardStyle() -> some View {
        self
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Constants.UI.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Constants.UI.cardCornerRadius, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
    }

    /// 条件修饰器
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - 标题栏 / 底栏 / 关于窗共用胶囊按钮
struct NetPulseCapsuleButtonStyle: ButtonStyle {
    enum Kind {
        case secondary
        case primary
        case destructive
    }

    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        NetPulseCapsuleButtonBody(configuration: configuration, kind: kind)
    }
}

private final class CapsuleHoverState: ObservableObject {
    @Published var hovering = false
}

private struct NetPulseCapsuleButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: NetPulseCapsuleButtonStyle.Kind
    @ObservedObject private var hover: CapsuleHoverState
    @Environment(\.colorScheme) private var colorScheme

    init(configuration: ButtonStyle.Configuration, kind: NetPulseCapsuleButtonStyle.Kind) {
        self.configuration = configuration
        self.kind = kind
        self.hover = CapsuleHoverState()
    }

    var body: some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule(style: .continuous)
                    .fill(fillColor)
            )
            .foregroundColor(foreground)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .onHover { hover.hovering = $0 }
    }

    private var fillColor: Color {
        switch kind {
        case .secondary:
            return Color.primary.opacity((hover.hovering || configuration.isPressed) ? 0.07 : 0)
        case .primary:
            return Color.netPulseDownload.opacity((hover.hovering || configuration.isPressed) ? 0.22 : 0.16)
        case .destructive:
            if hover.hovering || configuration.isPressed {
                return Color.netPulseRed.opacity(0.14)
            }
            return Color.clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .secondary:
            return .secondary
        case .primary:
            // 浅色模式用深青绿；深色模式用更亮的品牌青，保证对比
            return colorScheme == .dark
                ? Color.netPulseDownload
                : Color(hex: "007A76")
        case .destructive:
            return Color.netPulseRed
        }
    }
}

// MARK: - 外观偏好（设置窗 / 主弹窗 / 关于窗共用同一实例）
final class AppearancePreference: ObservableObject {
    static let shared = AppearancePreference()

    @Published private(set) var appearanceMode: AppSettings.AppearanceMode
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.appearanceMode = AppSettings.load().appearanceMode
        NotificationCenter.default.publisher(for: .settingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let loaded = AppSettings.load().appearanceMode
                if self.appearanceMode != loaded {
                    self.appearanceMode = loaded
                }
            }
            .store(in: &cancellables)
    }

    var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var themeIconName: String {
        switch appearanceMode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var themeLabel: String { appearanceMode.displayName }

    var nsAppearance: NSAppearance? {
        switch appearanceMode {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    func setMode(_ mode: AppSettings.AppearanceMode) {
        applyMode(mode, persistAndNotify: true)
    }

    /// 仅更新内存中的共用值，供「恢复默认设置」随整包落盘并广播一次
    func adoptMode(_ mode: AppSettings.AppearanceMode) {
        applyMode(mode, persistAndNotify: false)
    }

    private func applyMode(_ mode: AppSettings.AppearanceMode, persistAndNotify: Bool) {
        if appearanceMode != mode {
            appearanceMode = mode
        }
        guard persistAndNotify else { return }
        var s = AppSettings.load()
        s.appearanceMode = mode
        s.save()
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}

// MARK: - 历史日期相对中文
enum TrafficDateLabel {
    static func display(from yyyyMMdd: String, now: Date = Date()) -> String {
        let today = DateFormatter.yearMonthDay.string(from: now)
        if yyyyMMdd == today { return "今天" }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now),
           yyyyMMdd == DateFormatter.yearMonthDay.string(from: yesterday) {
            return "昨天"
        }
        if let date = DateFormatter.yearMonthDay.date(from: yyyyMMdd) {
            return monthDay(from: date)
        }
        return yyyyMMdd
    }

    static func monthDay(from date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}

// MARK: - NSColor 扩展
extension NSColor {
    /// 从十六进制颜色值初始化
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        // 强制 sRGB，避免设备色域导致菜单栏色偏
        self.init(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - String 扩展
extension String {
    /// 检查是否是有效的网络接口名称
    var isValidInterfaceName: Bool {
        !self.isEmpty && self.count <= 10
    }
}

// MARK: - Double 扩展
extension Double {
    /// 速度状态判断
    var speedStatus: SpeedStatus {
        let mbps = self / (1024 * 1024)
        if self <= 0 {
            return .disconnected
        } else if mbps < 0.1 {
            return .verySlow
        } else if mbps < 1 {
            return .slow
        } else if mbps < 5 {
            return .normal
        } else {
            return .good
        }
    }

    /// 速度状态枚举
    enum SpeedStatus {
        case disconnected
        case verySlow
        case slow
        case normal
        case good

        var color: Color {
            switch self {
            case .disconnected: return .netPulseRed
            case .verySlow: return .netPulseRed
            case .slow: return .netPulseOrange
            case .normal: return .netPulseBlue
            case .good: return .netPulseGreen
            }
        }
    }
}


// MARK: - 程序图标（菜单栏 / 设置预览共用，禁止 template）
enum NetPulseAppIcon {
    /// 原始 AppIcon 资源
    static func sourceImage() -> NSImage {
        if let icon = NSApp.applicationIconImage, icon.size.width > 0 {
            return icon
        }
        if let named = NSImage(named: NSImage.applicationIconName), named.size.width > 0 {
            return named
        }
        if let named = NSImage(named: "AppIcon"), named.size.width > 0 {
            return named
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let fromFile = NSImage(contentsOfFile: path), fromFile.size.width > 0 {
            return fromFile
        }
        return NSImage(size: NSSize(width: Constants.UI.menuBarIconSize, height: Constants.UI.menuBarIconSize))
    }

    /// 菜单栏尺寸的彩色图标（isTemplate = false，避免发白/发黑）
    static func menuBarImage() -> NSImage {
        let size = Constants.UI.menuBarIconSize
        let source = sourceImage()
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
        img.isTemplate = false
        return img
    }

    static func cornerRadius(for side: CGFloat) -> CGFloat {
        side * Constants.UI.appIconCornerRatio
    }
}
