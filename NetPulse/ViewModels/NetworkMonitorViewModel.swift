import Foundation
import Combine
import SwiftUI

/// 网络监控视图模型：产出统一 StatusBarSnapshot，速度历史用环形缓冲
final class NetworkMonitorViewModel: ObservableObject {
    // MARK: - Published
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
    @Published var wifiName: String = "未连接 Wi-Fi"

    @Published var ipAddress: String = "--"
    @Published var gatewayAddress: String = "--"
    @Published var signalStrength: String = "--"
    @Published var recentTrafficRecords: [TrafficRecord] = []
    @Published var hasSSID: Bool = false
    @Published var locationPermissionNeeded: Bool = false
    @Published var activeInterfaceType: NetworkInterface.InterfaceType = .other
    @Published var isWiFiInterface: Bool = false

    @Published var cpuUsageText: String = "0%"
    @Published var memoryUsageText: String = "0%"

    /// 面板波形用（由环形缓冲导出）
    @Published var speedHistory: [SpeedPoint] = []
    /// 预格式化波形序列（KB/s），面板少做重复 map
    @Published var downloadHistoryKBps: [Double] = []
    @Published var uploadHistoryKBps: [Double] = []

    @Published var menuBarDisplayMode: AppSettings.MenuBarDisplayMode {
        didSet { rebuildStatusBarSnapshot() }
    }

    /// 状态栏唯一数据源
    @Published private(set) var statusBarSnapshot = StatusBarSnapshot()

    var networkTitle: String {
        if hasSSID, !wifiName.isEmpty {
            return wifiName
        }
        if !activeInterfaceName.isEmpty, activeInterfaceName != "检测中..." {
            return activeInterfaceName
        }
        return wifiName
    }

    var networkStatusIcon: String {
        if !isConnected {
            return isWiFiInterface ? "wifi.slash" : "network"
        }
        return activeInterfaceType.systemImage
    }

    // MARK: - 私有
    private let networkService: NetworkMonitorService
    private let storageService: StorageService
    private var settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var previousBytesIn: UInt64 = 0
    private var previousBytesOut: UInt64 = 0
    private let maxHistoryCount = 30
    private var speedRing = RingBuffer<SpeedPoint>(capacity: 30)

    init(networkService: NetworkMonitorService,
         storageService: StorageService = .shared,
         settings: AppSettings = AppSettings.load()) {
        self.networkService = networkService
        self.storageService = storageService
        self.settings = settings
        self.menuBarDisplayMode = settings.menuBarDisplayMode
        setupBindings()
        startTemperatureMonitor()
        rebuildStatusBarSnapshot()
    }

    func startMonitoring() {
        networkService.startMonitoring()
        startTemperatureMonitor()
    }

    func stopMonitoring() {
        networkService.stopMonitoring()
        CPUTemperatureMonitor.shared.stop()
    }
    func getSettings() -> AppSettings { settings }

    func resetTodayTraffic() {
        storageService.resetTodayTraffic()
        previousBytesIn = 0
        previousBytesOut = 0
    }

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

        networkService.$hasSSID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.hasSSID = value
            }
            .store(in: &cancellables)

        networkService.$locationPermissionNeeded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.locationPermissionNeeded = value
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
        let deltaIn: UInt64
        let deltaOut: UInt64

        if previousBytesIn == 0 && previousBytesOut == 0 {
            deltaIn = 0
            deltaOut = 0
        } else {
            deltaIn = stats.totalDownloaded >= previousBytesIn ? stats.totalDownloaded - previousBytesIn : 0
            deltaOut = stats.totalUploaded >= previousBytesOut ? stats.totalUploaded - previousBytesOut : 0
        }

        storageService.updateTodayTraffic(downloaded: deltaIn, uploaded: deltaOut, currentStats: stats)

        previousBytesIn = stats.totalDownloaded
        previousBytesOut = stats.totalUploaded

        downloadSpeedText = stats.formattedDownloadSpeed
        uploadSpeedText = stats.formattedUploadSpeed
        totalDownloadText = stats.formattedTotalDownload
        totalUploadText = stats.formattedTotalUpload
        isConnected = stats.isConnected
        activeInterfaceName = stats.activeInterface

        menuBarSpeedText = ByteFormatter.formatSpeedCompact(stats.downloadSpeed)
        menuBarUploadSpeedText = ByteFormatter.formatSpeedCompact(stats.uploadSpeed)
        menuBarIcon = "app"

        let downSpeed = menuBarSpeedText
        let upSpeed = menuBarUploadSpeedText
        menuBarDualSpeedText = "↓\(downSpeed) ↑\(upSpeed)"

        let today = storageService.todayTraffic
        todayDownload = ByteFormatter.formatBytes(today.downloadBytes)
        todayUpload = ByteFormatter.formatBytes(today.uploadBytes)

        checkTrafficLimit(today: today)
        recentTrafficRecords = storageService.getRecentTrafficRecords(days: 5)

        ipAddress = networkService.currentIPAddress
        gatewayAddress = networkService.gatewayAddress
        signalStrength = networkService.signalStrength
        hasSSID = networkService.hasSSID
        locationPermissionNeeded = networkService.locationPermissionNeeded
        if let iface = networkService.activeInterface {
            activeInterfaceType = iface.type
        } else {
            activeInterfaceType = .other
        }
        isWiFiInterface = activeInterfaceType == .wifi

        // 系统指标：与网速同拍采样一次，写入快照，状态栏不再二次采样
        let metrics = SystemMetricsProvider.sample()
        cpuUsageText = metrics.cpuText
        memoryUsageText = metrics.memText

        speedRing.append(SpeedPoint(
            timestamp: Date(),
            downloadSpeed: stats.downloadSpeed,
            uploadSpeed: stats.uploadSpeed
        ))
        let history = speedRing.asArray()
        speedHistory = history
        downloadHistoryKBps = history.map { $0.downloadSpeed / 1024 }
        uploadHistoryKBps = history.map { $0.uploadSpeed / 1024 }

        publishSnapshot(
            down: downSpeed,
            up: upSpeed,
            dual: menuBarDualSpeedText,
            metrics: metrics
        )
    }

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

    private func rebuildStatusBarSnapshot() {
        let metrics = SystemMetricsProvider.sample()
        let down = ByteFormatter.formatSpeedCompact(networkService.currentStats.downloadSpeed)
        let up = ByteFormatter.formatSpeedCompact(networkService.currentStats.uploadSpeed)
        menuBarSpeedText = down
        menuBarUploadSpeedText = up
        menuBarDualSpeedText = "↓\(down) ↑\(up)"
        menuBarIcon = "app"
        publishSnapshot(down: down, up: up, dual: menuBarDualSpeedText, metrics: metrics)
    }

    private func publishSnapshot(down: String, up: String, dual: String, metrics: SystemMetricsSnapshot) {
        var snap = StatusBarSnapshot()
        snap.displayMode = menuBarDisplayMode
        snap.downloadSpeedText = down
        snap.uploadSpeedText = up
        snap.dualSpeedText = dual
        snap.cpuPercent = metrics.cpuPercent
        snap.memPercent = metrics.memPercent
        snap.diskPercent = metrics.diskPercent
        snap.cpuText = metrics.cpuText
        snap.memText = metrics.memText
        snap.diskText = metrics.diskText
        snap.diskAvailable = metrics.diskAvailable
        snap.menuBarIcon = "app"
        let reading = CPUTemperatureMonitor.shared.latest
        snap.cpuTemperatureText = reading.menuBarTitle
        snap.cpuTemperatureCelsius = reading.celsius
        // 写入节流：相等则跳过，减少状态栏重绘
        if snap != statusBarSnapshot {
            statusBarSnapshot = snap
        }
    }

    private func startTemperatureMonitor() {
        let monitor = CPUTemperatureMonitor.shared
        monitor.onUpdate = { [weak self] _ in
            self?.rebuildStatusBarSnapshot()
        }
        monitor.start(intervalSeconds: 1.5)
    }

    func updateSettings(_ newSettings: AppSettings? = nil) {
        let loaded = newSettings ?? AppSettings.load()
        settings = loaded
        menuBarDisplayMode = loaded.menuBarDisplayMode
        networkService.updateSettings(loaded)
        rebuildStatusBarSnapshot()
        objectWillChange.send()
    }

    func reloadSettings() { updateSettings() }
}
