import Foundation
import Network
import Combine
import CoreWLAN
import Darwin

/// 网络监控服务：采样在 workQueue；主线程只收结果
final class NetworkMonitorService: ObservableObject {
    @Published private(set) var currentStats = NetworkStats()
    @Published private(set) var isConnected = false
    @Published private(set) var activeInterface: NetworkInterface?
    @Published private(set) var availableInterfaces: [NetworkInterface] = []
    @Published private(set) var wifiName: String = "检测中…"
    @Published private(set) var currentIPAddress: String = "--"
    @Published private(set) var gatewayAddress: String = "--"
    @Published private(set) var signalStrength: String = "--"
    /// 已读到真实 SSID（标题优先用它）
    @Published private(set) var hasSSID: Bool = false
    /// Wi-Fi 已连接但因位置权限读不到名称
    @Published private(set) var locationPermissionNeeded: Bool = false

    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.netpulse.networkmonitor", qos: .utility)
    private let workQueue = DispatchQueue(label: "com.netpulse.network.work", qos: .utility)
    private let trafficCalculator = TrafficCalculator()
    private var updateTimer: DispatchSourceTimer?
    private var settings: AppSettings
    private var isPausedForSleep = false
    private var wifiBSDName: String?
    private var primaryHint: String?
    private let gatewayCache = GatewayCache(ttl: 45)
    /// 当前生效的采样间隔；未变则不重建 Timer
    private var activeUpdateInterval: TimeInterval = 0

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.monitor = NWPathMonitor()
        NetPulseLog.debug("NetworkMonitorService 初始化")
        LocationPermissionService.shared.requestIfNeeded()
        trafficCalculator.updateSelection(
            selected: settings.selectedInterface,
            primaryHint: nil,
            wifiBSD: nil
        )
    }

    deinit {
        NetPulseLog.debug("NetworkMonitorService 释放")
        stopMonitoring()
    }

    func startMonitoring() {
        NetPulseLog.info("启动网络监控")
        setupMonitor()
        monitor.start(queue: monitorQueue)
        startTrafficUpdates(forceRebuild: true)
    }

    func stopMonitoring() {
        NetPulseLog.info("停止网络监控")
        monitor.cancel()
        stopTrafficTimer()
    }

    func pauseForSleep() {
        isPausedForSleep = true
        stopTrafficTimer()
    }

    func resumeAfterWake() {
        isPausedForSleep = false
        trafficCalculator.resetSync()
        gatewayCache.invalidate()
        NotificationCenter.default.post(name: .networkDidWakeReset, object: nil)
        startTrafficUpdates(forceRebuild: true)
        workQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateTrafficStats()
        }
    }

    func updateSettings(_ newSettings: AppSettings) {
        let intervalChanged = abs(newSettings.updateInterval - settings.updateInterval) > 0.001
        self.settings = newSettings
        trafficCalculator.updateSelection(
            selected: newSettings.selectedInterface,
            primaryHint: primaryHint,
            wifiBSD: wifiBSDName
        )
        if !isPausedForSleep {
            startTrafficUpdates(forceRebuild: intervalChanged)
        }
    }

    func refreshInterfaces() {
        trafficCalculator.getNetworkInterfaces { [weak self] interfaces in
            DispatchQueue.main.async {
                self?.availableInterfaces = interfaces
            }
        }
    }

    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.workQueue.async {
                self.handlePathUpdate(path)
            }
        }
    }

    private func handlePathUpdate(_ path: NWPath) {
        let connected = path.status == .satisfied

        let wifiBSD = CWWiFiClient.shared().interface()?.interfaceName
        wifiBSDName = wifiBSD

        var hint: String?
        if let wifiBSD = wifiBSD, !wifiBSD.isEmpty {
            hint = wifiBSD
        } else if let wifi = path.availableInterfaces.first(where: { $0.type == .wifi }) {
            hint = wifi.name
        } else if let eth = path.availableInterfaces.first(where: { $0.type == .wiredEthernet }) {
            hint = eth.name
        }
        primaryHint = hint

        trafficCalculator.updateSelection(
            selected: settings.selectedInterface,
            primaryHint: hint,
            wifiBSD: wifiBSD
        )

        let interfaces = trafficCalculator.getNetworkInterfacesSync()

        var selected: NetworkInterface?
        let selectedName = settings.selectedInterface
        if !selectedName.isEmpty {
            selected = interfaces.first { $0.name == selectedName }
        }
        if selected == nil, let resolved = TrafficLogic.resolveCountedInterface(
            selected: selectedName,
            primaryHint: hint,
            wifiBSD: wifiBSD,
            activeEnInterfaces: interfaces.filter { $0.name.hasPrefix("en") && $0.isActive }.map(\.name)
        ) {
            selected = interfaces.first { $0.name == resolved }
        }
        if selected == nil {
            selected = interfaces.first { $0.type == .wifi || $0.type == .ethernet }
        }
        if selected == nil {
            selected = interfaces.first
        }

        gatewayCache.invalidate()
        let wifi = getCurrentWiFiName(fallbackInterface: selected)
        let ip = getIPAddress(preferred: selected?.name ?? wifiBSD)
        let gateway = gatewayCache.get(force: true)
        let signal = getSignalStrength()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let wasConnected = self.isConnected
            self.isConnected = connected
            self.availableInterfaces = interfaces
            self.activeInterface = selected
            self.wifiName = wifi.name
            self.hasSSID = wifi.hasSSID
            self.locationPermissionNeeded = wifi.needsLocation
            self.currentIPAddress = ip
            self.gatewayAddress = gateway
            self.signalStrength = signal
            self.currentStats.isConnected = connected
            self.currentStats.activeInterface = selected?.displayName ?? wifi.name

            if wasConnected != connected {
                NotificationCenter.default.post(
                    name: .networkStatusChanged,
                    object: nil,
                    userInfo: ["isConnected": connected]
                )
                if self.settings.notificationsEnabled && self.settings.disconnectNotificationEnabled {
                    if !connected {
                        NotificationService.shared.sendDisconnectNotification()
                    } else {
                        NotificationService.shared.sendReconnectNotification(speed: "...")
                    }
                }
            }
            NetPulseLog.debug("网络状态: \(connected ? "已连接" : "已断开"), 接口: \(self.currentStats.activeInterface)")
        }
    }

    private func getCurrentWiFiName(fallbackInterface: NetworkInterface?) -> (name: String, hasSSID: Bool, needsLocation: Bool) {
        LocationPermissionService.shared.requestIfNeeded()
        let wifiClient = CWWiFiClient.shared()
        let needsLocationForWiFi = !LocationPermissionService.shared.isAuthorized
        if let interface = wifiClient.interface() {
            if let ssid = interface.ssid(), !ssid.isEmpty {
                return (ssid, true, false)
            }
            let bsd = interface.interfaceName ?? wifiBSDName
            if let bsd = bsd, !bsd.isEmpty {
                return (NetworkInterface.getDisplayName(for: bsd), false, needsLocationForWiFi)
            }
        }
        if let fallback = fallbackInterface {
            let needs = fallback.type == .wifi && needsLocationForWiFi
            return (fallback.displayName, false, needs)
        }
        if let bsd = wifiBSDName {
            return (NetworkInterface.getDisplayName(for: bsd), false, needsLocationForWiFi)
        }
        return ("未连接", false, false)
    }

    private func getIPAddress(preferred: String?) -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return "--" }
        defer { freeifaddrs(ifaddr) }

        var preferredIP: String?
        var fallbackIP: String?

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let info = ptr?.pointee else { continue }
            let name = String(cString: info.ifa_name)
            guard let addr = info.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard name.hasPrefix("en") else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                              &hostname, socklen_t(hostname.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: hostname)
            if let preferred = preferred, name == preferred {
                preferredIP = ip
            } else if fallbackIP == nil {
                fallbackIP = ip
            }
        }
        return preferredIP ?? fallbackIP ?? "--"
    }

    private func getSignalStrength() -> String {
        if let interface = CWWiFiClient.shared().interface() {
            let rssi = interface.rssiValue()
            if rssi != 0 && rssi != 127 {
                return "\(rssi) dBm"
            }
        }
        return "--"
    }

    private func stopTrafficTimer() {
        workQueue.async { [weak self] in
            self?.updateTimer?.cancel()
            self?.updateTimer = nil
            self?.activeUpdateInterval = 0
        }
    }

    /// 仅在 interval 真变或强制时重建 Timer；定时器跑在 workQueue，不占主线程
    private func startTrafficUpdates(forceRebuild: Bool) {
        let interval = max(settings.updateInterval, 1.0)
        workQueue.async { [weak self] in
            guard let self = self else { return }
            if !forceRebuild, self.updateTimer != nil, abs(self.activeUpdateInterval - interval) < 0.001 {
                return
            }
            self.updateTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.workQueue)
            timer.schedule(deadline: .now() + 0.2, repeating: interval, leeway: .milliseconds(50))
            timer.setEventHandler { [weak self] in
                self?.updateTrafficStats()
            }
            timer.resume()
            self.updateTimer = timer
            self.activeUpdateInterval = interval
            NetPulseLog.debug("流量定时器间隔: \(interval)s")
        }
    }

    private func updateTrafficStats() {
        guard !isPausedForSleep else { return }
        trafficCalculator.updateSelection(
            selected: settings.selectedInterface,
            primaryHint: primaryHint,
            wifiBSD: wifiBSDName
        )
        let gw = gatewayCache.get(force: false)
        trafficCalculator.calculate { [weak self] stats in
            DispatchQueue.main.async {
                guard let self = self else { return }
                var merged = stats
                merged.isConnected = self.isConnected
                if merged.activeInterface.isEmpty || merged.activeInterface == "无活动" {
                    merged.activeInterface = self.activeInterface?.displayName ?? self.wifiName
                }
                self.currentStats = merged
                self.gatewayAddress = gw
            }
        }
    }
}

extension Notification.Name {
    static let networkStatusChanged = Notification.Name("com.netpulse.networkStatusChanged")
    static let trafficAlert = Notification.Name("com.netpulse.trafficAlert")
    static let networkDidWakeReset = Notification.Name("com.netpulse.networkDidWakeReset")
}
