import Foundation
import UserNotifications

/// Local notifications for new agent messages while the app isn't focused on that chat.
/// Gated by the "sesameNotifications" setting.
final class Notifier: NSObject, @unchecked Sendable {
    static let shared = Notifier()

    var enabled: Bool { UserDefaults.standard.object(forKey: "sesameNotifications") as? Bool ?? true }

    private var authorized = false

    func requestAuthorizationIfEnabled() {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    func post(agent: Agent, body: String) {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = agent.name
            content.body = String(body.prefix(180))
            content.sound = .default
            content.threadIdentifier = agent.rawValue
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(req)
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    // Show banners even while the app is running (but a different chat/space is focused).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
