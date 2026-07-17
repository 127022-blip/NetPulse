import Foundation
import ServiceManagement

/// 登录项服务 - 管理应用启动项
final class LoginItemService {
    static let shared = LoginItemService()

    private init() {}

    /// 检查是否已启用登录项
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }

    /// 启用登录项
    func enable() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                print("[NetPulse] 登录项已启用")
            } catch {
                print("[NetPulse] 启用登录项失败: \(error)")
            }
        }
    }

    /// 禁用登录项
    func disable() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
                print("[NetPulse] 登录项已禁用")
            } catch {
                print("[NetPulse] 禁用登录项失败: \(error)")
            }
        }
    }

    /// 更新登录项状态
    func update(enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }
}
