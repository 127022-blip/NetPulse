import Foundation
import UserNotifications

/// 通知服务 - 负责发送各种系统通知
final class NotificationService: NSObject, ObservableObject {
    // MARK: - 单例
    static let shared = NotificationService()

    // MARK: - 属性
    @Published private(set) var isAuthorized = false

    private let notificationCenter = UNUserNotificationCenter.current()

    // MARK: - 初始化
    private override init() {
        super.init()
        notificationCenter.delegate = self
        checkAuthorizationStatus()
    }

    // MARK: - 公开方法

    /// 请求通知权限
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                if let error = error {
                    print("[NetPulse] 通知授权错误: \(error)")
                }
                completion?(granted)
            }
        }
    }

    /// 检查通知授权状态
    func checkAuthorizationStatus() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    /// 发送网络断开通知
    func sendDisconnectNotification() {
        sendNotification(
            type: .disconnect,
            body: "网络连接已断开"
        )
    }

    /// 发送网络恢复通知
    /// - Parameter speed: 恢复时的网速
    func sendReconnectNotification(speed: String) {
        sendNotification(
            type: .reconnect,
            body: "网络已恢复，当前速度 \(speed)"
        )
    }

    /// 发送网速过慢通知
    /// - Parameter speed: 当前网速
    func sendSlowSpeedNotification(speed: String) {
        sendNotification(
            type: .slowSpeed,
            body: "网速低于阈值，当前速度 \(speed)"
        )
    }

    /// 发送流量超限通知
    /// - Parameter usage: 当前已用流量
    func sendHighTrafficNotification(usage: String) {
        sendNotification(
            type: .highTraffic,
            body: "今日流量已使用 \(usage)"
        )
    }

    // MARK: - 私有方法

    /// 发送通知
    private func sendNotification(type: NotificationType, body: String) {
        guard isAuthorized else {
            print("[NetPulse] 通知未授权，跳过发送")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "NETPULSE_ALERT"

        // 使用通知类型作为标识符，便于管理
        let request = UNNotificationRequest(
            identifier: "\(type.rawValue)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // 立即发送
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("[NetPulse] 发送通知失败: \(error)")
            }
        }
    }

    /// 移除所有待发送的通知
    func removeAllPendingNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    /// 移除所有已显示的通知
    func removeAllDeliveredNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationService: UNUserNotificationCenterDelegate {
    /// 应用在前台时收到通知的回调
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // 在前台也显示通知
        completionHandler([.banner, .sound])
    }

    /// 用户点击通知的回调
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        print("[NetPulse] 用户点击了通知: \(identifier)")
        completionHandler()
    }
}
