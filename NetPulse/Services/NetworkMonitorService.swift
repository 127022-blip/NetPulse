import Foundation
import Network
import Combine
import CoreWLAN
import Darwin

/// 网络监控服务 - 核心服务，负责实时监控网络状态和流量
final class NetworkMonitorService: ObservableObject {
    // MARK: - Published 属性
    @Published private(set) var currentStats = NetworkStats()
    @Published private(set) var isConnected = false
    @Published private(set) var activeInterface: NetworkInterface?
    @Published private(set) var availableInterfaces: [NetworkInterface] = []
    @Published private(set) var wifiName: String = "未连接WiFi"
    @Published private(set) var currentIPAddress: String = "--"
    @Published private(set) var gatewayAddress: String = "--"
    @Published private(set) var signalStrength: String = "--"

    // MARK: - 私有属性
    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.netpulse.networkmonitor", qos: .utility)
    private var trafficCalculator: TrafficCalculator
    private var updateTimer: Timer?
    private var settings: AppSettings

    // MARK: - 初始化
    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.trafficCalculator = TrafficCalculator()
        self.monitor = NWPathMonitor()
        print("[NetPulse] NetworkMonitorService 初始化")
    }

    deinit {
        print("[NetPulse] NetworkMonitorService 释放")
        stopMonitoring()
    }

    // MARK: - 公开方法

    /// 开始监控网络
    func startMonitoring() {
        print("[NetPulse] 启动网络监控...")
        setupMonitor()  // 先设置监控处理器
        monitor.start(queue: monitorQueue)
        startTrafficUpdates()
        print("[NetPulse] 网络监控已启动")
    }

    /// 停止监控网络
    func stopMonitoring() {
        print("[NetPulse] 停止网络监控")
        monitor.cancel()
        updateTimer?.invalidate()
        updateTimer = nil
    }

    /// 更新设置
    func updateSettings(_ newSettings: AppSettings) {
        self.settings = newSettings
    }

    /// 获取当前网络接口列表
    func refreshInterfaces() {
        let interfaces = trafficCalculator.getNetworkInterfaces()
        DispatchQueue.main.async {
            self.availableInterfaces = interfaces
        }
    }

    // MARK: - 私有方法

    /// 设置网络路径监控
    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handlePathUpdate(path)
            }
        }
    }

    /// 处理网络路径更新
    private func handlePathUpdate(_ path: NWPath) {
        let wasConnected = isConnected
        isConnected = path.status == .satisfied

        // 刷新接口列表
        let interfaces = trafficCalculator.getNetworkInterfaces()
        availableInterfaces = interfaces

        // 选择活跃接口
        if let selectedName = settings.selectedInterface.isEmpty ? nil : settings.selectedInterface {
            activeInterface = interfaces.first { $0.name == selectedName }
        }

        if activeInterface == nil {
            activeInterface = interfaces.first { $0.type == .wifi || $0.type == .ethernet }
        }

        if activeInterface == nil && !interfaces.isEmpty {
            activeInterface = interfaces.first
        }

        // 获取 Wi-Fi 名称
        wifiName = getCurrentWiFiName()
        
        // 获取网络详细信息
        currentIPAddress = getIPAddress()
        gatewayAddress = getGatewayAddress()
        signalStrength = getSignalStrength()

        currentStats.isConnected = isConnected
        currentStats.activeInterface = activeInterface?.displayName ?? wifiName

        if wasConnected != isConnected {
            NotificationCenter.default.post(
                name: .networkStatusChanged,
                object: nil,
                userInfo: ["isConnected": isConnected]
            )

            // 发送断网/恢复通知
            if settings.disconnectNotificationEnabled {
                if !isConnected {
                    NotificationService.shared.sendDisconnectNotification()
                } else {
                    NotificationService.shared.sendReconnectNotification(speed: "...")
                }
            }
        }

        print("[NetPulse] 网络状态: \(isConnected ? "已连接" : "已断开"), 接口: \(currentStats.activeInterface), WiFi: \(wifiName)")
    }

    /// 获取当前连接的 Wi-Fi 名称
    private func getCurrentWiFiName() -> String {
        print("[NetPulse] getCurrentWiFiName 开始调用")
        
        // 优先使用 system_profiler 获取 Wi-Fi 名称（最可靠）
        if let wifiName = getWiFiNameFromSystemProfiler() {
            print("[NetPulse] getCurrentWiFiName 返回: \(wifiName)")
            return wifiName
        }
        
        // 备用方案：使用 CoreWLAN
        let wifiClient = CWWiFiClient.shared()
        if let interface = wifiClient.interface() {
            if let ssid = interface.ssid(), !ssid.isEmpty {
                print("[NetPulse] getCurrentWiFiName CoreWLAN 返回: \(ssid)")
                return ssid
            }
        }
        
        // 最后备用：返回IP地址
        let ip = getInterfaceIPAddress() ?? "未连接WiFi"
        print("[NetPulse] getCurrentWiFiName IP返回: \(ip)")
        return ip
    }
    
    /// 使用 system_profiler 获取 Wi-Fi 名称
    private func getWiFiNameFromSystemProfiler() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPAirPortDataType", "-json"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8),
               let jsonData = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let airportData = json["SPAirPortDataType"] as? [[String: Any]],
               let firstInterface = airportData.first,
               let interfaces = firstInterface["spairport_airport_interfaces"] as? [[String: Any]] {
                // 遍历所有接口，找 en1 且有 current_network_information 的
                for iface in interfaces {
                    if let name = iface["_name"] as? String, name == "en1",
                       let currentNetwork = iface["spairport_current_network_information"] as? [String: Any],
                       let wifiName = currentNetwork["_name"] as? String {
                        print("[NetPulse] system_profiler 找到 Wi-Fi: \(wifiName)")
                        return wifiName
                    }
                }
            }
        } catch {
            print("[NetPulse] system_profiler 获取WiFi名称失败: \(error)")
        }
        return nil
    }
    
    /// 获取 IP 地址
    private func getIPAddress() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return "--" }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let info = ptr?.pointee else { continue }
            let name = String(cString: info.ifa_name)
            
            // 查找活跃的 Wi-Fi 或以太网接口
            if (name == "en0" || name == "en1") && info.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(info.ifa_addr, socklen_t(info.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: hostname)
                }
            }
        }
        return "--"
    }
    
    /// 获取网关地址
    private func getGatewayAddress() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/route")
        task.arguments = ["-n", "get", "default"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // 查找 gateway 字段
                let lines = output.components(separatedBy: "\n")
                for line in lines {
                    if line.contains("gateway:") {
                        let components = line.components(separatedBy: ":")
                        if components.count > 1 {
                            return components[1].trimmingCharacters(in: .whitespaces)
                        }
                    }
                }
            }
        } catch {
            print("[NetPulse] 获取网关地址失败: \(error)")
        }
        return "--"
    }
    
    /// 获取 Wi-Fi 信号强度
    private func getSignalStrength() -> String {
        // 使用 system_profiler 获取信号强度
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPAirPortDataType", "-json"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8),
               let jsonData = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let airportData = json["SPAirPortDataType"] as? [[String: Any]],
               let firstInterface = airportData.first,
               let interfaces = firstInterface["spairport_airport_interfaces"] as? [[String: Any]] {
                for iface in interfaces {
                    if let name = iface["_name"] as? String, name == "en1",
                       let currentNetwork = iface["spairport_current_network_information"] as? [String: Any],
                       let signalNoise = currentNetwork["spairport_signal_noise"] as? String {
                        // 格式: "-38 dBm / -91 dBm"
                        let components = signalNoise.components(separatedBy: "/")
                        if let signal = components.first {
                            return signal.trimmingCharacters(in: .whitespaces)
                        }
                    }
                }
            }
        } catch {
            print("[NetPulse] 获取信号强度失败: \(error)")
        }
        return "--"
    }
    
    /// 获取接口IP地址
    private func getInterfaceIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let info = ptr?.pointee else { continue }
            let name = String(cString: info.ifa_name)
            
            if name == "en1" && info.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(info.ifa_addr, socklen_t(info.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: hostname)
                }
            }
        }
        return nil
    }

    /// 开始流量更新定时器
    private func startTrafficUpdates() {
        updateTimer?.invalidate()
        let interval = 2.0  // 固定2秒刷新
        updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateTrafficStats()
        }
        RunLoop.main.add(updateTimer!, forMode: .common)
        print("[NetPulse] 流量更新定时器已启动，间隔: \(interval)s")
    }

    /// 更新流量统计
    private func updateTrafficStats() {
        trafficCalculator.calculate { [weak self] stats in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.currentStats = stats
                self.currentStats.isConnected = self.isConnected
                self.currentStats.activeInterface = self.activeInterface?.displayName ?? ""
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let networkStatusChanged = Notification.Name("com.netpulse.networkStatusChanged")
    static let trafficAlert = Notification.Name("com.netpulse.trafficAlert")
}
