import Foundation
import Network
import Combine
import CoreWLAN
import Darwin

/// 网络监控服务 - 核心服务，负责实时监控网络状态和流量
final class NetworkMonitorService: ObservableObject {
    @Published private(set) var currentStats = NetworkStats()
    @Published private(set) var isConnected = false
    @Published private(set) var activeInterface: NetworkInterface?
    @Published private(set) var availableInterfaces: [NetworkInterface] = []
    @Published private(set) var wifiName: String = "检测中…"
    @Published private(set) var currentIPAddress: String = "--"
    @Published private(set) var gatewayAddress: String = "--"
    @Published private(set) var signalStrength: String = "--"

    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.netpulse.networkmonitor", qos: .utility)
    private let workQueue = DispatchQueue(label: "com.netpulse.network.work", qos: .utility)
    private let trafficCalculator = TrafficCalculator()
    private var updateTimer: Timer?
    private var settings: AppSettings
    private var isPausedForSleep = false
    private var wifiBSDName: String?
    private var primaryHint: String?
    private let gatewayCache = GatewayCache(ttl: 45)

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.monitor = NWPathMonitor()
        print("[NetPulse] NetworkMonitorService 初始化")
        LocationPermissionService.shared.requestIfNeeded()
        trafficCalculator.updateSelection(
            selected: settings.selectedInterface,
            primaryHint: nil,
            wifiBSD: nil
        )
    }

    deinit {
        print("[NetPulse] NetworkMonitorService 释放")
        stopMonitoring()
    }

    func startMonitoring() {
        print("[NetPulse] 启动网络监控...")
        setupMonitor()
        monitor.start(queue: monitorQueue)
        startTrafficUpdates()
        print("[NetPulse] 网络监控已启动")
    }

    func stopMonitoring() {
        print("[NetPulse] 停止网络监控")
        monitor.cancel()
        stopTrafficTimer()
    }

    func pauseForSleep() {
        print("[NetPulse] pauseForSleep")
        isPausedForSleep = true
        stopTrafficTimer()
    }

    func resumeAfterWake() {
        print("[NetPulse] resumeAfterWake")
        isPausedForSleep = false
        trafficCalculator.resetSync()
        gatewayCache.invalidate()
        NotificationCenter.default.post(name: .networkDidWakeReset, object: nil)
        startTrafficUpdates()
        workQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateTrafficStats()
        }
    }

    func updateSettings(_ newSettings: AppSettings) {
        self.settings = newSettings
        trafficCalculator.updateSelection(
            selected: newSettings.selectedInterface,
            primaryHint: primaryHint,
            wifiBSD: wifiBSDName
        )
        if !isPausedForSleep {
            startTrafficUpdates()
        }
    }

    func refreshInterfaces() {
        trafficCalculator.getNetworkInterfaces { [weak self] interfaces in
            DispatchQueue.main.async {
                self?.availableInterfaces = interfaces
            }
        }
    }

    // MARK: - 私有

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

        // 只选一个主物理接口提示
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

        // path 变化时强制刷新网关
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
            self.wifiName = wifi
            self.currentIPAddress = ip
            self.gatewayAddress = gateway
            self.signalStrength = signal
            self.currentStats.isConnected = connected
            self.currentStats.activeInterface = selected?.displayName ?? wifi

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
            print("[NetPulse] 网络状态: \(connected ? "已连接" : "已断开"), 接口: \(self.currentStats.activeInterface), WiFi: \(wifi), BSD: \(wifiBSD ?? "-")")
        }
    }

    /// SSID：有权限且 CoreWLAN 返回时用真名；否则诚实降级为接口显示名，绝不伪装「未连接」
    private func getCurrentWiFiName(fallbackInterface: NetworkInterface?) -> String {
        LocationPermissionService.shared.requestIfNeeded()
        let wifiClient = CWWiFiClient.shared()
        if let interface = wifiClient.interface() {
            if let ssid = interface.ssid(), !ssid.isEmpty {
                return ssid
            }
            // 有 Wi‑Fi 接口但拿不到 SSID → 权限或系统限制
            let bsd = interface.interfaceName ?? wifiBSDName
            if let bsd = bsd, !bsd.isEmpty {
                let display = NetworkInterface.getDisplayName(for: bsd)
                if !LocationPermissionService.shared.isAuthorized {
                    return "\(display)（需位置权限以显示名称）"
                }
                return display
            }
        }
        if let fallback = fallbackInterface {
            return fallback.displayName
        }
        if let bsd = wifiBSDName {
            return NetworkInterface.getDisplayName(for: bsd)
        }
        return "无 Wi‑Fi 接口"
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
        DispatchQueue.main.async { [weak self] in
            self?.updateTimer?.invalidate()
            self?.updateTimer = nil
        }
    }

    private func startTrafficUpdates() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateTimer?.invalidate()
            let interval = max(self.settings.updateInterval, 1.0)
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.updateTrafficStats()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.updateTimer = timer
            print("[NetPulse] 流量更新定时器已启动，间隔: \(interval)s")
        }
    }

    private func updateTrafficStats() {
        guard !isPausedForSleep else { return }
        trafficCalculator.updateSelection(
            selected: settings.selectedInterface,
            primaryHint: primaryHint,
            wifiBSD: wifiBSDName
        )
        // 低频刷新网关（缓存 TTL 内直接返回）
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
