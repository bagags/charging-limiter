import ChargingLimiterCore
import Foundation
import UserNotifications

enum NotificationPermission: Equatable {
    case unknown
    case allowed
    case denied
}

@MainActor
final class NotificationCoordinator {
    private enum Keys {
        static let wasOver = "notification.wasOverLimit"
        static let previousLimit = "notification.previousLimit"
    }

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private var tracker: OverLimitTracker

    init(center: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
        tracker = OverLimitTracker(
            wasOverLimit: defaults.bool(forKey: Keys.wasOver),
            previousLimit: defaults.object(forKey: Keys.previousLimit) as? Int ?? 80
        )
    }

    func requestPermission() async -> NotificationPermission {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return .denied
        }
        return await permissionState()
    }

    func permissionState() async -> NotificationPermission {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }

    func process(percent: Int, limit: Int) async {
        let shouldNotify = tracker.update(percent: percent, limit: limit)
        persistTracker()
        guard shouldNotify, await permissionState() == .allowed else { return }

        let content = UNMutableNotificationContent()
        content.title = "Battery above charge limit"
        content.body = "Battery is at \(percent)%, above your \(limit)% limit."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "charging-limit-exceeded",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private func persistTracker() {
        defaults.set(tracker.wasOverLimit, forKey: Keys.wasOver)
        defaults.set(tracker.previousLimit, forKey: Keys.previousLimit)
    }
}
