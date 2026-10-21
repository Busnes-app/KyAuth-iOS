import UserNotifications

/// Rebuilds every KyIdentity alert from fixed text, so nothing the relay or APNs sent is shown. The
/// sealed payload is opened only to pick the title; the app opens it again with its own copy of the
/// keys, so a push this extension could not open is still checked there.
final class NotificationService: UNNotificationServiceExtension {
    private var pending: (request: UNNotificationRequest, handler: (UNNotificationContent) -> Void)?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        pending = (request, contentHandler)
        let fields = try? PushPayload.fields(request.content.userInfo, keys: PushKeyStore.load())
        deliver(purpose: fields?["purpose"] as? String)
    }

    /// Out of time before the payload was opened: still show the fixed text, never what was sent.
    override func serviceExtensionTimeWillExpire() {
        deliver(purpose: nil)
    }

    private func deliver(purpose: String?) {
        guard let (request, handler) = pending else { return }
        pending = nil
        let content = UNMutableNotificationContent()
        content.title = PushPayload.alertTitle(purpose: purpose)
        content.body = PushPayload.alertBody
        content.sound = .default
        content.categoryIdentifier = "MFA_CHALLENGE"
        content.userInfo = request.content.userInfo
        handler(content)
    }
}
