import Foundation
import SwiftUI

// MARK: - Color 扩展
extension Color {
    /// 应用主题颜色
    static let netPulseGreen = Color(hex: "34C759")      // 网速良好
    static let netPulseBlue = Color(hex: "007AFF")       // 网速正常
    static let netPulseOrange = Color(hex: "FF9500")     // 网速较慢
    static let netPulseRed = Color(hex: "FF3B30")        // 网络断开
    static let netPulseGray = Color(hex: "8E8E93")       // 空闲状态

    /// 从十六进制颜色值初始化
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
    /// 添加圆角和阴影
    func cardStyle() -> some View {
        self
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(Constants.UI.panelCornerRadius)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
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

        self.init(
            red: CGFloat(r) / 255,
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
