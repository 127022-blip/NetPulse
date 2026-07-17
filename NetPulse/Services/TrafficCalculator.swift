import Foundation

/// 流量计算服务
final class TrafficCalculator {
    // MARK: - 私有属性
    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastTimestamp: Date?

    // 接口计数值缓存 (接口名 -> 字节数)
    private var interfaceBytesCache: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]

    // 是否准备好
    private var isReady = false

    // MARK: - 初始化
    init() {}

    // MARK: - 公开方法

    /// 获取所有网络接口列表
    func getNetworkInterfaces() -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []

        let output = runCommand("/usr/sbin/netstat", "-i", "-b")
        guard let output = output else { return interfaces }

        let lines = output.components(separatedBy: "\n")
        for line in lines {
            // 跳过表头、空行、以太网详情行
            if line.isEmpty || line.hasPrefix("Kernel") || line.hasPrefix("Name") || line.hasPrefix("Ibytes") || line.contains("Link#") {
                continue
            }

            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            // 需要至少 11 列: name, mtu, network, address, ipkts, ierr, ibytes, opkts, oerr, obytes, coll
            guard components.count >= 10 else { continue }

            let name = String(components[0])

            // 跳过不需要的接口
            if name.hasPrefix("lo") || name.hasPrefix("utun") || name.hasPrefix("awdl") || name.hasPrefix("gif") || name.hasPrefix("stf") || name.hasPrefix("anpi") || name.hasPrefix("ap") || name.hasPrefix("bridge") || name.contains("*") {
                continue
            }

            // 解析字节数 (Ibytes 在第 6 位, Obytes 在第 9 位)
            guard let bytesIn = UInt64(components[6]),
                  let bytesOut = UInt64(components[9]) else {
                continue
            }

            let interfaceType = NetworkInterface.inferType(from: name)
            let displayName = NetworkInterface.getDisplayName(for: name)

            let interface = NetworkInterface(
                name: name,
                displayName: displayName,
                type: interfaceType,
                isActive: bytesIn > 0 || bytesOut > 0,
                currentBytesIn: bytesIn,
                currentBytesOut: bytesOut
            )
            interfaces.append(interface)
        }

        return interfaces
    }

    /// 计算当前网络流量和速度
    func calculate(completion: @escaping (NetworkStats) -> Void) {
        var stats = NetworkStats()

        let output = runCommand("/usr/sbin/netstat", "-i", "-b")
        guard let output = output else {
            completion(stats)
            return
        }

        let currentTimestamp = Date()
        let lines = output.components(separatedBy: "\n")

        var totalBytesIn: UInt64 = 0
        var totalBytesOut: UInt64 = 0
        var activeInterfaceName = ""

        for line in lines {
            // 跳过表头、空行、以太网详情行
            if line.isEmpty || line.hasPrefix("Kernel") || line.hasPrefix("Name") || line.hasPrefix("Ibytes") || line.contains("Link#") {
                continue
            }

            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 10 else { continue }

            let name = String(components[0])

            // 跳过不需要的接口
            if name.hasPrefix("lo") || name.hasPrefix("utun") || name.hasPrefix("awdl") || name.hasPrefix("gif") || name.hasPrefix("stf") || name.hasPrefix("anpi") || name.hasPrefix("ap") || name.hasPrefix("bridge") || name.contains("*") {
                continue
            }

            // 解析字节数
            guard let bytesIn = UInt64(components[6]),
                  let bytesOut = UInt64(components[9]) else {
                continue
            }

            // 记录活跃接口
            if bytesIn > 0 || bytesOut > 0 {
                if activeInterfaceName.isEmpty {
                    activeInterfaceName = NetworkInterface.getDisplayName(for: name)
                }

                // 计算增量
                if let cached = interfaceBytesCache[name] {
                    let deltaIn = bytesIn >= cached.bytesIn ? bytesIn - cached.bytesIn : 0
                    let deltaOut = bytesOut >= cached.bytesOut ? bytesOut - cached.bytesOut : 0
                    totalBytesIn += deltaIn
                    totalBytesOut += deltaOut
                }
            }

            // 更新缓存
            interfaceBytesCache[name] = (bytesIn, bytesOut)
        }

        // 第一次调用：只建立缓存
        if !isReady {
            isReady = true
            lastTimestamp = currentTimestamp
            stats.activeInterface = activeInterfaceName.isEmpty ? "无活动" : activeInterfaceName
            stats.isConnected = !activeInterfaceName.isEmpty
            completion(stats)
            return
        }

        // 计算时间间隔
        let timeInterval = lastTimestamp.map { currentTimestamp.timeIntervalSince($0) } ?? 1.0
        guard timeInterval > 0 else {
            completion(stats)
            return
        }

        // 计算速度 (bytes per second)
        stats.downloadSpeed = Double(totalBytesIn) / timeInterval
        stats.uploadSpeed = Double(totalBytesOut) / timeInterval

        // 累计总量
        stats.totalDownloaded = lastBytesIn + totalBytesIn
        stats.totalUploaded = lastBytesOut + totalBytesOut

        // 更新上一次的值
        lastBytesIn = stats.totalDownloaded
        lastBytesOut = stats.totalUploaded
        lastTimestamp = currentTimestamp

        stats.timestamp = currentTimestamp
        stats.activeInterface = activeInterfaceName.isEmpty ? "无活动" : activeInterfaceName
        stats.isConnected = !activeInterfaceName.isEmpty

        completion(stats)
    }

    /// 重置计数器
    func reset() {
        lastBytesIn = 0
        lastBytesOut = 0
        lastTimestamp = nil
        interfaceBytesCache.removeAll()
        isReady = false
    }

    // MARK: - 私有方法

    private func runCommand(_ arguments: String...) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
