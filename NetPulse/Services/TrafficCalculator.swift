import Foundation
import Darwin

/// 流量计算服务：状态收敛到单一串行队列；计数用 getifaddrs，禁止 netstat 子进程
final class TrafficCalculator {
    private let queue = DispatchQueue(label: "com.netpulse.traffic.serial", qos: .utility)

    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastTimestamp: Date?
    private var interfaceBytesCache: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var isReady = false

    private var selectedInterfaceName: String = ""
    private var primaryHint: String?
    private var wifiBSDName: String?

    init() {}

    // MARK: - 设置（全部进同队列）

    /// 同步写入选中网卡，避免异步竞态导致本拍仍用旧选择
    func updateSelection(selected: String, primaryHint: String?, wifiBSD: String?) {
        queue.sync {
            self.selectedInterfaceName = selected
            self.primaryHint = primaryHint
            self.wifiBSDName = wifiBSD
        }
    }

    /// 异步版本（非热路径可用）
    func updateSelectionAsync(selected: String, primaryHint: String?, wifiBSD: String?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.selectedInterfaceName = selected
            self.primaryHint = primaryHint
            self.wifiBSDName = wifiBSD
        }
    }

    func reset() {
        queue.async { [weak self] in
            self?.resetLocked()
        }
    }

    func resetSync() {
        queue.sync { resetLocked() }
    }

    private func resetLocked() {
        lastBytesIn = 0
        lastBytesOut = 0
        lastTimestamp = nil
        interfaceBytesCache.removeAll()
        isReady = false
    }

    // MARK: - 公开方法

    func getNetworkInterfaces(completion: @escaping ([NetworkInterface]) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                completion([])
                return
            }
            completion(self.readInterfacesLocked())
        }
    }

    func getNetworkInterfacesSync() -> [NetworkInterface] {
        queue.sync { readInterfacesLocked() }
    }

    func calculate(completion: @escaping (NetworkStats) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                completion(NetworkStats())
                return
            }
            completion(self.calculateLocked())
        }
    }

    // MARK: - 私有（queue 内）

    private func readInterfacesLocked() -> [NetworkInterface] {
        let counters = Self.readInterfaceCounters()
        var interfaces: [NetworkInterface] = []
        for (name, bytes) in counters.sorted(by: { $0.key < $1.key }) {
            if shouldSkipInterface(name) { continue }
            interfaces.append(NetworkInterface(
                name: name,
                displayName: NetworkInterface.getDisplayName(for: name),
                type: NetworkInterface.inferType(from: name),
                isActive: bytes.in > 0 || bytes.out > 0,
                currentBytesIn: bytes.in,
                currentBytesOut: bytes.out
            ))
        }
        return interfaces
    }

    private func calculateLocked() -> NetworkStats {
        var stats = NetworkStats()
        let currentTimestamp = Date()
        let counters = Self.readInterfaceCounters()
        let previousCache = interfaceBytesCache

        for (name, bytes) in counters {
            if shouldSkipInterface(name) { continue }
            interfaceBytesCache[name] = (bytes.in, bytes.out)
        }

        let activeEn = counters
            .filter { name, bytes in
                name.hasPrefix("en") && !shouldSkipInterface(name) && (bytes.in > 0 || bytes.out > 0)
            }
            .sorted { a, b in (a.value.in + a.value.out) > (b.value.in + b.value.out) }
            .map { $0.key }

        let enCandidates: [String] = {
            if !activeEn.isEmpty { return activeEn }
            return counters.keys.filter { $0.hasPrefix("en") && !shouldSkipInterface($0) }.sorted()
        }()

        guard let target = TrafficLogic.resolveCountedInterface(
            selected: selectedInterfaceName,
            primaryHint: primaryHint,
            wifiBSD: wifiBSDName,
            activeEnInterfaces: enCandidates
        ), let current = counters[target] else {
            stats.activeInterface = "无活动"
            stats.isConnected = false
            stats.timestamp = currentTimestamp
            return stats
        }

        let display = NetworkInterface.getDisplayName(for: target)
        let prev = previousCache[target]
        let deltaIn = TrafficLogic.delta(current: current.in, previous: prev.map { $0.bytesIn })
        let deltaOut = TrafficLogic.delta(current: current.out, previous: prev.map { $0.bytesOut })

        stats.activeInterface = display
        stats.isConnected = true
        stats.timestamp = currentTimestamp

        if TrafficLogic.shouldDiscardFirstSample(isReady: isReady) {
            isReady = true
            lastTimestamp = currentTimestamp
            return stats
        }

        let timeInterval = lastTimestamp.map { currentTimestamp.timeIntervalSince($0) } ?? 1.0
        if TrafficLogic.shouldIgnoreShortInterval(timeInterval) {
            stats.totalDownloaded = lastBytesIn
            stats.totalUploaded = lastBytesOut
            return stats
        }

        if TrafficLogic.shouldDiscardSpeedForLongInterval(timeInterval) {
            lastTimestamp = currentTimestamp
            lastBytesIn += deltaIn
            lastBytesOut += deltaOut
            stats.totalDownloaded = lastBytesIn
            stats.totalUploaded = lastBytesOut
            return stats
        }

        stats.downloadSpeed = TrafficLogic.speed(bytes: deltaIn, interval: timeInterval)
        stats.uploadSpeed = TrafficLogic.speed(bytes: deltaOut, interval: timeInterval)
        stats.totalDownloaded = lastBytesIn + deltaIn
        stats.totalUploaded = lastBytesOut + deltaOut
        lastBytesIn = stats.totalDownloaded
        lastBytesOut = stats.totalUploaded
        lastTimestamp = currentTimestamp
        return stats
    }

    private func shouldSkipInterface(_ name: String) -> Bool {
        name.hasPrefix("lo")
            || name.hasPrefix("utun")
            || name.hasPrefix("awdl")
            || name.hasPrefix("gif")
            || name.hasPrefix("stf")
            || name.hasPrefix("anpi")
            || name.hasPrefix("ap")
            || name.hasPrefix("bridge")
            || name.hasPrefix("llw")
            || name.hasPrefix("nan")
            || name.contains("*")
    }

    /// getifaddrs(AF_LINK / if_data) 读取累计字节，替代 netstat 子进程
    static func readInterfaceCounters() -> [String: (in: UInt64, out: UInt64)] {
        var result: [String: (in: UInt64, out: UInt64)] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return result }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let name = String(cString: p.pointee.ifa_name)
            guard let addr = p.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let dataPtr = p.pointee.ifa_data else { continue }
            let data = dataPtr.assumingMemoryBound(to: if_data.self)
            result[name] = (UInt64(data.pointee.ifi_ibytes), UInt64(data.pointee.ifi_obytes))
        }
        return result
    }
}
