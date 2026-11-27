import SwiftUI
import UIKit
import UserNotifications

/// Notification permission and APNs registration. Asked for after the first successful sync, never at first launch.
enum Push {
    /// TestFlight and App Store builds talk to Apple's production push service.
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    @MainActor
    static func requestIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        case .denied:
            break
        @unknown default:
            break
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

/// Push delivery and taps. A tap (or a `dealdesk://deal/<id>` link) opens that deal.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            Store.shared.registerDevice(token: hex)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            Store.shared.pushProblem = message
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
        Task { @MainActor in
            Store.shared.kick()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let dealId = response.notification.request.content.userInfo["dealId"] as? String
        completionHandler()
        Task { @MainActor in
            if let dealId { Router.shared.openDeal(dealId) }
            Store.shared.kick()
        }
    }
}

/// Which tab is showing, and the Deals tab's navigation, so pushes and links can open a deal.
@MainActor
final class Router: ObservableObject {
    static let shared = Router()

    @Published var tab: AppTab = .deals
    @Published var dealsPath: [String] = []

    func openDeal(_ id: String) {
        guard Router.isValidId(id) else { return }
        tab = .deals
        dealsPath = [id]
    }

    /// `dealdesk://deal/<id>`
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "dealdesk", url.host?.lowercased() == "deal" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        if let id = parts.first { openDeal(id) }
    }

    static func isValidId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 80 && id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }
}

enum AppTab: Hashable {
    case deals, reviewed, save, rules
}

enum Haptics {
    @MainActor static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor static func tap() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @MainActor static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
