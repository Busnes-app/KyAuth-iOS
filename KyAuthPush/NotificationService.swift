import UserNotifications

/// Rebuilds every KyIdentity alert from fixed text, so nothing the relay or APNs sent is shown. The
/// sealed payload is opened only to pick the title; the app opens it again with its own copy of the
/// keys, so a push this extension could not open is still checked there.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let fields = try? PushPayload.fields(request.content.userInfo, keys: PushKeyStore.load())
        let content = UNMutableNotificationContent()
        content.title = PushPayload.alertTitle(purpose: fields?["purpose"] as? String)
        content.body = PushPayload.alertBody
        content.sound = .default
        content.categoryIdentifier = "MFA_CHALLENGE"
        content.userInfo = request.content.userInfo
        contentHandler(content)
    }
}
