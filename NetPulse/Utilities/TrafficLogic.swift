import Foundation

/// 纯逻辑：接口选择 / 首样本 / 休眠间隔 / 跨日归档（可供单测）
enum TrafficLogic {
    /// 自动模式选出唯一主接口 BSD 名
    /// - Parameters:
    ///   - selected: 用户手动选择（非空则直接用）
    ///   - primaryHint: 来自 NWPath/CoreWLAN 的主接口提示（可空）
    ///   - wifiBSD: CoreWLAN Wi‑Fi BSD 名
    ///   - activeEnInterfaces: 当前活跃的 en* 接口（已按流量/活跃度排序，优先在前）
    static func resolveCountedInterface(
        selected: String,
        primaryHint: String?,
        wifiBSD: String?,
        activeEnInterfaces: [String]
    ) -> String? {
        let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let hint = primaryHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
            return hint
        }
        if let wifi = wifiBSD?.trimmingCharacters(in: .whitespacesAndNewlines), !wifi.isEmpty {
            return wifi
        }
        return activeEnInterfaces.first
    }

    /// 是否应丢弃速率样本（首样本校准）
    static func shouldDiscardFirstSample(isReady: Bool) -> Bool {
        !isReady
    }

    /// 休眠/超长间隔：丢弃速率，但可累计字节
    static func shouldDiscardSpeedForLongInterval(_ interval: TimeInterval, threshold: TimeInterval = 30) -> Bool {
        interval > threshold
    }

    /// 过短间隔：忽略本拍
    static func shouldIgnoreShortInterval(_ interval: TimeInterval, minimum: TimeInterval = 0.05) -> Bool {
        interval <= minimum
    }

    /// 跨日：给定上次重置日与今日字符串，是否需要归档并清零
    static func shouldArchiveForNewDay(lastResetDate: String?, today: String) -> Bool {
        guard let last = lastResetDate else { return false }
        return last != today
    }

    /// 计算单接口增量（计数回绕时归零）
    static func delta(current: UInt64, previous: UInt64?) -> UInt64 {
        guard let previous = previous else { return 0 }
        return current >= previous ? current - previous : 0
    }

    /// 速度 = 增量 / 间隔
    static func speed(bytes: UInt64, interval: TimeInterval) -> Double {
        guard interval > 0 else { return 0 }
        return Double(bytes) / interval
    }
}
