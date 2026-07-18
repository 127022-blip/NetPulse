import Foundation

/// 网络统计数据模型
struct NetworkStats: Identifiable, Equatable {
    let id = UUID()

    /// 下载速度 (bytes per second)
    var downloadSpeed: Double = 0

    /// 上传速度 (bytes per second)
    var uploadSpeed: Double = 0

    /// 当前下载总字节数
    var totalDownloaded: UInt64 = 0

    /// 当前上传总字节数
    var totalUploaded: UInt64 = 0

    /// 峰值下载速度
    var peakDownloadSpeed: Double = 0

    /// 峰值上传速度
    var peakUploadSpeed: Double = 0

    /// 网络是否连接
    var isConnected: Bool = true

    /// 活跃的网络接口名称
    var activeInterface: String = ""

    /// 更新时间戳
    var timestamp: Date = Date()

    /// 格式化下载速度字符串
    var formattedDownloadSpeed: String {
        ByteFormatter.formatSpeed(downloadSpeed)
    }

    /// 格式化上传速度字符串
    var formattedUploadSpeed: String {
        ByteFormatter.formatSpeed(uploadSpeed)
    }

    /// 格式化总下载量
    var formattedTotalDownload: String {
        ByteFormatter.formatBytes(totalDownloaded)
    }

    /// 格式化总上传量
    var formattedTotalUpload: String {
        ByteFormatter.formatBytes(totalUploaded)
    }
}

/// 网络接口信息模型
struct NetworkInterface: Identifiable, Hashable {
    let id = UUID()

    /// 接口名称 (如 en0, en1, utun2)
    let name: String

    /// 显示名称 (如 Wi-Fi, 以太网, VPN)
    let displayName: String

    /// 接口类型
    let type: InterfaceType

    /// 是否活跃
    var isActive: Bool = false

    /// 当前流量
    var currentBytesIn: UInt64 = 0
    var currentBytesOut: UInt64 = 0

    /// 网络接口类型枚举
    enum InterfaceType: String {
        case wifi = "Wi-Fi"
        case ethernet = "Ethernet"
        case vpn = "VPN"
        case cellular = "Cellular"
        case loopback = "Loopback"
        case other = "Other"

        var systemImage: String {
            switch self {
            case .wifi: return "wifi"
            case .ethernet: return "cable.connector"
            case .vpn: return "network.badge.shield.half.filled"
            case .cellular: return "antenna.radiowaves.left.and.right"
            case .loopback: return "arrow.triangle.2.circlepath"
            case .other: return "network"
            }
        }
    }

    /// 根据接口名称推断类型
    static func inferType(from name: String) -> InterfaceType {
        if name.hasPrefix("en") {
            // 通常 en0 是 Wi-Fi, en1 是以太网
            if name == "en0" {
                return .wifi
            } else {
                return .ethernet
            }
        } else if name.hasPrefix("utun") || name.hasPrefix("ppp") {
            return .vpn
        } else if name.hasPrefix("lo") {
            return .loopback
        } else {
            return .other
        }
    }

    /// 获取显示名称
    static func getDisplayName(for name: String) -> String {
        if name.hasPrefix("en0") {
            return "Wi-Fi"
        } else if name.hasPrefix("en") {
            return "以太网 (\(name))"
        } else if name.hasPrefix("utun") {
            return "VPN (\(name))"
        } else if name.hasPrefix("awdl") {
            return "AirDrop (\(name))"
        } else {
            return name
        }
    }
}

/// 流量统计记录 (用于历史数据存储)
struct TrafficRecord: Identifiable, Codable, Equatable {
    var id: UUID
    let date: String          // YYYY-MM-DD 格式
    var downloadBytes: UInt64
    var uploadBytes: UInt64
    var peakDownloadSpeed: Double
    var peakUploadSpeed: Double
    var createdAt: String

    init(id: UUID? = nil, date: String = "", downloadBytes: UInt64 = 0, uploadBytes: UInt64 = 0, peakDownloadSpeed: Double = 0, peakUploadSpeed: Double = 0, createdAt: String = "") {
        self.id = id ?? UUID()
        self.date = date
        self.downloadBytes = downloadBytes
        self.uploadBytes = uploadBytes
        self.peakDownloadSpeed = peakDownloadSpeed
        self.peakUploadSpeed = peakUploadSpeed
        self.createdAt = createdAt
    }

    // 自定义 Codable 实现，处理旧数据没有 id 的情况
    enum CodingKeys: String, CodingKey {
        case id, date, downloadBytes, uploadBytes, peakDownloadSpeed, peakUploadSpeed, createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 先解码 date（必须）
        date = try container.decode(String.self, forKey: .date)
        // 尝试解码 id，如果不存在则用 date 生成稳定的 UUID
        if let existingId = try? container.decode(UUID.self, forKey: .id) {
            id = existingId
        } else {
            // 用 date 字符串生成确定性的 UUID（每次解码同一 date 得到相同 UUID）
            let uuidString = "00000000-0000-0000-0000-\(String(format: "%012d", abs(date.hashValue) % 1000000000000))"
            id = UUID(uuidString: uuidString) ?? UUID()
        }
        downloadBytes = try container.decode(UInt64.self, forKey: .downloadBytes)
        uploadBytes = try container.decode(UInt64.self, forKey: .uploadBytes)
        peakDownloadSpeed = try container.decode(Double.self, forKey: .peakDownloadSpeed)
        peakUploadSpeed = try container.decode(Double.self, forKey: .peakUploadSpeed)
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }

    static var today: TrafficRecord {
        TrafficRecord(
            date: DateFormatter.yearMonthDay.string(from: Date()),
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}

/// 速度数据点 (用于波型图)
struct SpeedPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let downloadSpeed: Double  // bytes per second
    let uploadSpeed: Double    // bytes per second
}
