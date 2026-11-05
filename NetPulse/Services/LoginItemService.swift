import Foundation
import ServiceManagement

/// 登录项服务（部署目标 ≥ 13，与 SMAppService 对齐）
final class LoginItemService {
    static let shared = LoginItemService()

    private(set) var lastErrorMessage: String?

    private init() {}

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    func enable() -> Bool {
        do {
            try SMAppService.mainApp.register()
            lastErrorMessage = nil
            print("[NetPulse] 登录项已启用")
            return true
        } catch {
            lastErrorMessage = "无法启用登录项：\(error.localizedDescription)。请到「系统设置 → 通用 → 登录项」手动添加 NetPulse。"
            print("[NetPulse] 启用登录项失败: \(error)")
            return false
        }
    }

    @discardableResult
    func disable() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            lastErrorMessage = nil
            print("[NetPulse] 登录项已禁用")
            return true
        } catch {
            lastErrorMessage = "无法关闭登录项：\(error.localizedDescription)"
            print("[NetPulse] 禁用登录项失败: \(error)")
            return false
        }
    }

    @discardableResult
    func update(enabled: Bool) -> Bool {
        enabled ? enable() : disable()
    }
}
