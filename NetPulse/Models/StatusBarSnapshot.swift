import Foundation

/// 状态栏统一指标快照：主线程只消费本结构，禁止二次采样
struct StatusBarSnapshot: Equatable {
    var displayMode: AppSettings.MenuBarDisplayMode = .iconAndSystem
    var downloadSpeedText: String = "   0KB"
    var uploadSpeedText: String = "   0KB"
    var dualSpeedText: String = ""
    var cpuPercent: Double = 0
    var memPercent: Double = 0
    var diskPercent: Double = 0
    var cpuText: String = "0%"
    var memText: String = "0%"
    var diskText: String = "0%"
    /// 磁盘采样是否有效；失败时 diskText 为 "--%"
    var diskAvailable: Bool = true
    var menuBarIcon: String = "app"
    /// 状态栏最末尾的 CPU 温度文案，如「42°」；读不到时为「--°」，禁止显示 0°
    var cpuTemperatureText: String = "--°"
    var cpuTemperatureCelsius: Double? = nil
}
