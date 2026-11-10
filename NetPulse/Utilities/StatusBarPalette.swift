import AppKit

/// 状态栏色板（全部 sRGB，集中管理，避免散落硬编码）
enum StatusBarPalette {
    /// 下载 #00C7BE
    static let download = NSColor(srgbRed: 0x00/255.0, green: 0xC7/255.0, blue: 0xBE/255.0, alpha: 1)
    /// 上传 #007AFF
    static let upload = NSColor(srgbRed: 0x00/255.0, green: 0x7A/255.0, blue: 0xFF/255.0, alpha: 1)
    /// 占用 ≤50 默认
    static let usageDefault = NSColor.textColor
    /// >50 黄 #FFD60A
    static let usageWarn = NSColor(srgbRed: 0xFF/255.0, green: 0xD6/255.0, blue: 0x0A/255.0, alpha: 1)
    /// >80 橙 #FF9F0A
    static let usageHigh = NSColor(srgbRed: 0xFF/255.0, green: 0x9F/255.0, blue: 0x0A/255.0, alpha: 1)
    /// >90 红 #FF453A
    static let usageCritical = NSColor(srgbRed: 0xFF/255.0, green: 0x45/255.0, blue: 0x3A/255.0, alpha: 1)

    /// 占用色阶（严格大于）：≤50 默认；>50 黄；>80 橙；>90 红
    static func usageColor(for percent: Double) -> NSColor {
        if percent > 90 { return usageCritical }
        if percent > 80 { return usageHigh }
        if percent > 50 { return usageWarn }
        return usageDefault
    }

    /// 将摄氏度映射为占用比例：上限 100°C，公式与 DropdownPanelView.temperatureBarPercent 一致：
    /// percent = min(max(celsius, 0) / 100, 1) × 100
    static func temperaturePercent(for celsius: Double) -> Double {
        min(max(celsius, 0) / 100.0, 1.0) * 100.0
    }

    /// 状态栏温度数字颜色：读到温度时按 temperaturePercent 再走 usageColor；读不到为次要灰，不把缺失当作 0 变色
    static func temperatureColor(for celsius: Double?) -> NSColor {
        guard let celsius else { return NSColor.secondaryLabelColor }
        return usageColor(for: temperaturePercent(for: celsius))
    }
}
