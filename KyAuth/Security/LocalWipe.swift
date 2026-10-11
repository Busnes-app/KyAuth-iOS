import Foundation
import UserNotifications

/// Erases everything KyAuth holds on this phone: the vault and its key, the device key, the pairing,
/// the pending sign-in request, the PIN and settings. KyIdentity still lists the device until it is
/// removed there; with its key gone, the device can no longer answer anything.
enum LocalWipe {
    private static let installedKey = "installed"

    static func eraseAll() {
        TotpVault.standard.delete()
        Keychain.deleteAll()
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        UserDefaults.standard.set(true, forKey: installedKey)
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Keychain items survive an uninstall; a fresh install must not inherit a pairing or vault key.
    static func clearLeftoversFromPreviousInstall() {
        guard !UserDefaults.standard.bool(forKey: installedKey) else { return }
        TotpVault.standard.delete()
        Keychain.deleteAll()
        UserDefaults.standard.set(true, forKey: installedKey)
    }
}
