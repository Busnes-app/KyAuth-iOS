import SwiftUI
import UIKit
import UserNotifications

@main
struct KyAuthApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(delegate.model)
                .onOpenURL { delegate.model.handleOpenURL($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Leaving the app locks it at once; the idle timer only covers the foreground.
                delegate.model.lock()
            case .active:
                delegate.model.checkIdle()
                delegate.model.retryUnsentResponses()
                Task { await delegate.model.refreshPendingChallenge() }
            default:
                break
            }
        }
    }
}

/// APNs registration and notification delivery. Every KyIdentity push goes through
/// `AppModel.handlePush`, whichever way it arrives.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let model: AppModel

    override init() {
        LocalWipe.clearLeftoversFromPreviousInstall()
        model = AppModel()
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "MFA_CHALLENGE", actions: [], intentIdentifiers: [], options: []),
        ])
        application.registerForRemoteNotifications()
        return true
    }

    /// Third-party keyboards can read and send anything typed, including TOTP setup keys and PINs.
    func application(
        _ application: UIApplication,
        shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier
    ) -> Bool {
        extensionPointIdentifier != .keyboard
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        model.didReceiveDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        model.didFailToRegisterForPush(error)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        await MainActor.run { model.handlePush(userInfo) }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run { model.handlePush(userInfo) }
    }
}
