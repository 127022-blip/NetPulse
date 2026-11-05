import Foundation
import SystemConfiguration

/// 默认网关缓存：低频刷新（默认 45 秒）或 path 变化时强制刷新
final class GatewayCache {
    private var cached: String = "--"
    private var lastRefresh: Date = .distantPast
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 45) {
        self.ttl = ttl
    }

    func get(force: Bool = false) -> String {
        let now = Date()
        if !force, now.timeIntervalSince(lastRefresh) < ttl, cached != "--" || lastRefresh != .distantPast {
            // 允许缓存 "--" 一小段时间，避免 path 抖动时狂刷
            if now.timeIntervalSince(lastRefresh) < ttl {
                return cached
            }
        }
        cached = Self.readGateway()
        lastRefresh = now
        return cached
    }

    func invalidate() {
        lastRefresh = .distantPast
    }

    /// SCDynamicStore State:/Network/Global/IPv4 → Router
    static func readGateway() -> String {
        guard let store = SCDynamicStoreCreate(nil, "NetPulseGateway" as CFString, nil, nil) else {
            return "--"
        }
        guard let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let router = value["Router"] as? String,
              !router.isEmpty else {
            return "--"
        }
        return router
    }
}
