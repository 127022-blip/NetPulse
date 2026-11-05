import Foundation
import Combine
import SwiftUI

/// 网络监控视图模型
final class NetworkMonitorViewModel: ObservableObject {
    // MARK: - Published 属性
    @Published var downloadSpeedText: String = "0 B/s"
    @Published private(set) var uploadSpeedText: String = "0 B/s"
    @Published var menuBarSpeedText: String = "   0KB"
    @Published var menuBarUploadSpeedText: String = "   0KB"
    @Published var totalDownloadText: String = "0 B"
    @Published var totalUploadText: String = "0 B"
    @Published var isConnected: Bool = true
    @Published var activeInterfaceName: String = "检测中..."
    @Published var menuBarIcon: String = "network"
    @Published var menuBarDualSpeedText: String = ""
    @Published var todayDownload: String = "0 B"
    @Published var todayUpload: String = "0 B"
    @Published var wifiName: String = "未连接WiFi"
    
    // 新增属性
    @Published var ipAddress: String = "--"
    @Published var gatewayAddress: String = "--"
    @Published var signalStrength: String = "--"
    @Published var recentTrafficRecords: [TrafficRecord] = []

    // CPU 使用率
    @Published var cpuUsageText: String = "0%"

    // 内存使用率
    @Published var memoryUsageText: String = "0%"
    
    // 流量波型数据
    @Published var speedHistory: [SpeedPoint] = []

    // 菜单栏显示模式
    @Published var menuBarDisplayMode: AppSettings.MenuBarDisplayMode {
        didSet { updateMenuBarDisplay() }
    }

    // MARK: - 私有属性
    private let networkService: NetworkMonitorService
    private let storageService: StorageService
    private var settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var previousBytesIn: UInt64 = 0
    private var previousBytesOut: UInt64 = 0
    private let maxHistoryCount = 30  // 保留30个数据点

    // MARK: - 初始化
    init(networkService: NetworkMonitorService,
         storageService: StorageService = .shared,
         settings: AppSettings = AppSettings.load()) {
        self.networkService = networkService
        self.storageService = storageService
        self.settings = settings
        self.menuBarDisplayMode = settings.menuBarDisplayMode
        setupBindings()
    }

    // MARK: - 公开方法
    func startMonitoring() {
        networkService.startMonitoring()
    }

    func stopMonitoring() {
        networkService.stopMonitoring()
    }

    func getSettings() -> AppSettings {
        return settings
    }

    func resetTodayTraffic() {
        storageService.resetTodayTraffic()
        previousBytesIn = 0
        previousBytesOut = 0
    }

    // MARK: - 私有方法
    private func setupBindings() {
        networkService.$currentStats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.updateUI(with: stats)
            }
            .store(in: &cancellables)

        networkService.$wifiName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.wifiName = name
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .networkDidWakeReset)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.previousBytesIn = 0
                self?.previousBytesOut = 0
            }
            .store(in: &cancellables)
    }

    private func updateUI(with stats: NetworkStats) {
        // 计算增量
        let deltaIn: UInt64
        let deltaOut: UInt64
        
        // 第一次更新时previousBytesIn为0，直接设为当前值，不计入增量
        if previousBytesIn == 0 && previousBytesOut == 0 {
            deltaIn = 0
            deltaOut = 0
        } else {
            deltaIn = stats.totalDownloaded >= previousBytesIn ? stats.totalDownloaded - previousBytesIn : 0
            deltaOut = stats.totalUploaded >= previousBytesOut ? stats.totalUploaded - previousBytesOut : 0
        }

        // 更新存储
        storageService.updateTodayTraffic(downloaded: deltaIn, uploaded: deltaOut, currentStats: stats)

        previousBytesIn = stats.totalDownloaded
        previousBytesOut = stats.totalUploaded

        // 更新显示
        downloadSpeedText = stats.formattedDownloadSpeed
        uploadSpeedText = stats.formattedUploadSpeed
        totalDownloadText = stats.formattedTotalDownload
        totalUploadText = stats.formattedTotalUpload
        isConnected = stats.isConnected
        activeInterfaceName = stats.activeInterface

        // 更新菜单栏图标标记（实际「仅图标」由 AppDelegate 使用 AppIcon 渲染）
        menuBarSpeedText = ByteFormatter.formatSpeedCompact(stats.downloadSpeed)
        menuBarUploadSpeedText = ByteFormatter.formatSpeedCompact(stats.uploadSpeed)
        menuBarIcon = "app"

        // 菜单栏双速度显示: ↓下载速度 ↑上传速度
        let downSpeed = ByteFormatter.formatSpeedCompact(stats.downloadSpeed)
        let upSpeed = ByteFormatter.formatSpeedCompact(stats.uploadSpeed)
        menuBarDualSpeedText = "↓\(downSpeed) ↑\(upSpeed)"

        // 更新今日流量
        let today = storageService.todayTraffic
        todayDownload = ByteFormatter.formatBytes(today.downloadBytes)
        todayUpload = ByteFormatter.formatBytes(today.uploadBytes)

        // 检查是否超过流量限制
        checkTrafficLimit(today: today)

        // 更新历史流量记录
        recentTrafficRecords = storageService.getRecentTrafficRecords(days: 5)
        
        // 更新网络详情
        ipAddress = networkService.currentIPAddress
        gatewayAddress = networkService.gatewayAddress
        signalStrength = networkService.signalStrength

        // 更新 CPU 使用率
        cpuUsageText = CPUMonitorService.shared.getFormattedCPUUsage()

        // 更新内存使用率
        memoryUsageText = MemoryMonitorService.shared.getFormattedMemoryUsage()
        
        // 更新速度历史（波型图）
        let newPoint = SpeedPoint(
            timestamp: Date(),
            downloadSpeed: stats.downloadSpeed,
            uploadSpeed: stats.uploadSpeed
        )
        speedHistory.append(newPoint)
        if speedHistory.count > maxHistoryCount {
            speedHistory.removeFirst()
        }
    }

    /// 检查流量限制与慢速告警（通知层自带防抖）
    private func checkTrafficLimit(today: TrafficRecord) {
        guard settings.notificationsEnabled else { return }

        if settings.trafficAlertEnabled {
            let totalUsed = today.downloadBytes + today.uploadBytes
            if totalUsed >= settings.dailyTrafficLimit {
                NotificationService.shared.sendHighTrafficNotification(usage: ByteFormatter.formatBytes(totalUsed))
            }
        }

        if settings.speedAlertEnabled && networkService.currentStats.isConnected {
            let down = networkService.currentStats.downloadSpeed
            if down > 0 && down < settings.speedThreshold {
                NotificationService.shared.sendSlowSpeedNotification(
                    speed: ByteFormatter.formatSpeed(down)
                )
            }
        }
    }

    /// 更新菜单栏显示
    private func updateMenuBarDisplay() {
        // 根据显示模式更新菜单栏文字
        let downSpeed = ByteFormatter.formatSpeedCompact(networkService.currentStats.downloadSpeed)
        let upSpeed = ByteFormatter.formatSpeedCompact(networkService.currentStats.uploadSpeed)
        let cpuUsage = CPUMonitorService.shared.getFormattedCPUUsage()

        switch menuBarDisplayMode {
        case .iconOnly:
            menuBarIcon = "app"
            menuBarSpeedText = "   0KB"
            menuBarUploadSpeedText = "   0KB"
            menuBarDualSpeedText = ""
        case .iconAndSpeed:
            menuBarIcon = "app"
            menuBarSpeedText = downSpeed
            menuBarUploadSpeedText = "   0KB"
            menuBarDualSpeedText = ""
        case .iconAndDualSpeed:
            menuBarIcon = "app"
            menuBarSpeedText = downSpeed
            menuBarUploadSpeedText = upSpeed
            menuBarDualSpeedText = "↓\(downSpeed) ↑\(upSpeed)"
        case .iconAndSystem:
            menuBarIcon = "app"
            menuBarSpeedText = downSpeed
            menuBarUploadSpeedText = upSpeed
            menuBarDualSpeedText = "↓\(downSpeed) ↑\(upSpeed)"
        case .iconWithCPU:
            menuBarIcon = "app"
            menuBarSpeedText = cpuUsage
            menuBarUploadSpeedText = "   0KB"
            menuBarDualSpeedText = ""
        }
    }

    /// 应用新设置：同步到网络服务并重建相关 Timer，立刻生效
    func updateSettings(_ newSettings: AppSettings? = nil) {
        let loaded = newSettings ?? AppSettings.load()
        settings = loaded
        menuBarDisplayMode = loaded.menuBarDisplayMode
        networkService.updateSettings(loaded)
        updateMenuBarDisplay()
        objectWillChange.send()
    }

    /// 兼容旧通知入口
    func reloadSettings() {
        updateSettings()
    }
}
