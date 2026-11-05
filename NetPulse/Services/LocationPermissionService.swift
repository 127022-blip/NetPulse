import Foundation
import CoreLocation

/// 位置权限：较新系统读取 Wi‑Fi SSID 需要；拒绝时诚实降级，不伪装断网
final class LocationPermissionService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPermissionService()

    private let manager = CLLocationManager()
    private(set) var authorizationStatus: CLAuthorizationStatus

    private override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .denied, .restricted, .notDetermined:
            return false
        default:
            return true
        }
    }

    /// 仅在未决定时请求；已拒绝不再弹窗
    func requestIfNeeded() {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
