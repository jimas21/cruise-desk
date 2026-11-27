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
        let content = response.notification.request.content
        let dealId = content.userInfo["dealId"] as? String
        let isAnswer = Router.isAnswerAlert(content.title)
        completionHandler()
        Task { @MainActor in
            if isAnswer {
                Router.shared.openAnswer(dealId, store: Store.shared)
            } else if let dealId {
                Router.shared.openDeal(dealId)
            }
            Store.shared.kick()
        }
    }
}

/// Which tab is showing, and the Deals tab's navigation, so pushes and links can open a deal or a thread.
@MainActor
final class Router: ObservableObject {
    static let shared = Router()

    @Published var tab: AppTab = .deals
    @Published var dealsPath: [String] = []
    /// The deal whose Ask thread should be scrolled into view when its detail shows.
    @Published var askFocus: String?
    /// The general "Ask Deal Desk" thread.
    @Published var showAsk = false

    func openDeal(_ id: String) {
        guard Router.isValidId(id) else { return }
        tab = .deals
        showAsk = false
        dealsPath = [id]
    }

    /// Opens a deal at its Ask thread, or the general thread when there is no deal.
    func openThread(dealId: String?) {
        tab = .deals
        if let dealId, Router.isValidId(dealId) {
            showAsk = false
            askFocus = dealId
            dealsPath = [dealId]
        } else {
            dealsPath = []
            showAsk = true
        }
    }

    /// An "Answer ready" push: its `dealId` names the deal asked about (or, defensively, the question itself).
    func openAnswer(_ id: String?, store: Store) {
        guard let id, Router.isValidId(id) else {
            openThread(dealId: nil)
            return
        }
        if store.deal(id) == nil, let question = store.question(id) {
            openThread(dealId: question.data.dealId)
        } else {
            openThread(dealId: id)
        }
    }

    /// `dealdesk://deal/<id>`, `dealdesk://deal/<id>/ask` and `dealdesk://ask`
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "dealdesk" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host?.lowercased() ?? "" {
        case "deal":
            guard let id = parts.first else { return }
            if parts.count > 1, parts[1].lowercased() == "ask" {
                openThread(dealId: id)
            } else {
                openDeal(id)
            }
        case "ask":
            openThread(dealId: nil)
        default:
            break
        }
    }

    nonisolated static func isAnswerAlert(_ title: String) -> Bool {
        title.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("answer ready")
    }

    nonisolated static func isValidId(_ id: String) -> Bool {
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
