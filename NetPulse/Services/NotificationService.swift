import Foundation
import AppKit
import UserNotifications

/// 通知服务 - 负责发送各种系统通知（固定 id 可替换 + 防抖）
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var isAuthorized = false
    /// 完整授权状态（供设置页展示与引导）
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let notificationCenter = UNUserNotificationCenter.current()

    /// 各类型上次发送时间（进程内）
    private var lastSentAt: [NotificationType: Date] = [:]
    /// 流量超限：每日一次记录
    private var highTrafficNotifiedDate: String?
    /// 慢速冷却（秒）
    private let slowSpeedCooldown: TimeInterval = 3600
    /// 断网/恢复最小间隔，避免抖动
    private let disconnectCooldown: TimeInterval = 30

    private let defaults = UserDefaults.standard
    private let highTrafficDateKey = "com.netpulse.highTrafficNotifiedDate"

    private override init() {
        super.init()
        notificationCenter.delegate = self
        highTrafficNotifiedDate = defaults.string(forKey: highTrafficDateKey)
        checkAuthorizationStatus()
    }

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

    func checkAuthorizationStatus() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    /// 打开系统「通知」设置，便于用户手动开启权限
    func openSystemNotificationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications",
            "x-apple.systempreferences:com.apple.Notifications-Settings"
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// 设置页展示用的权限文案
    var authorizationStatusText: String {
        switch authorizationStatus {
        case .authorized: return "已授权"
        case .denied: return "已拒绝"
        case .notDetermined: return "尚未请求"
        case .provisional: return "临时授权"
        case .ephemeral: return "临时授权"
        @unknown default: return "未知"
        }
    }

    func sendDisconnectNotification() {
        sendNotification(type: .disconnect, body: "网络连接已断开", cooldown: disconnectCooldown)
    }

    func sendReconnectNotification(speed: String) {
        sendNotification(type: .reconnect, body: "网络已恢复，当前速度 \(speed)", cooldown: disconnectCooldown)
    }

    func sendSlowSpeedNotification(speed: String) {
        sendNotification(type: .slowSpeed, body: "网速低于阈值，当前速度 \(speed)", cooldown: slowSpeedCooldown)
    }

    /// 流量超限：同一自然日最多一次；同时 1 小时冷却兜底
    func sendHighTrafficNotification(usage: String) {
        let today = DateFormatter.yearMonthDay.string(from: Date())
        if highTrafficNotifiedDate == today {
            print("[NetPulse] 今日流量通知已发送，跳过")
            return
        }
        let sent = sendNotification(type: .highTraffic, body: "今日流量已使用 \(usage)", cooldown: 3600)
        if sent {
            highTrafficNotifiedDate = today
            defaults.set(today, forKey: highTrafficDateKey)
        }
    }

    @discardableResult
    private func sendNotification(type: NotificationType, body: String, cooldown: TimeInterval) -> Bool {
        guard isAuthorized else {
            print("[NetPulse] 通知未授权，跳过发送")
            return false
        }

        if let last = lastSentAt[type], Date().timeIntervalSince(last) < cooldown {
            print("[NetPulse] 通知防抖跳过: \(type.rawValue)")
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "NETPULSE_ALERT"

        // 固定 identifier：同类型替换而非堆叠
        let identifier = "com.netpulse.\(type.rawValue)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        notificationCenter.add(request) { error in
            if let error = error {
                print("[NetPulse] 发送通知失败: \(error)")
            }
        }
        lastSentAt[type] = Date()
        return true
    }

    func removeAllPendingNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    func removeAllDeliveredNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        print("[NetPulse] 用户点击了通知: \(response.notification.request.identifier)")
        completionHandler()
    }
}
