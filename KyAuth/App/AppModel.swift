import CryptoKit
import Foundation
import LocalAuthentication
import Observation
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// App state and workflows. Views read it and call its actions; everything security-relevant
/// (locking, prompts, signatures, network calls) happens here.
@MainActor
@Observable
final class AppModel {
    enum LockState: Equatable {
        case locked
        /// Face ID passed; the optional PIN is still required.
        case needsPin
        case unlocked
    }

    private(set) var lockState: LockState = .locked
    private(set) var entries: [TotpEntry] = []
    private(set) var vaultError: String?
    private(set) var account: PairedAccount?
    private(set) var pendingChallenge: MfaChallenge? = MfaChallengeStore.load()
    private(set) var pushState = PushStore.load()
    private(set) var pinEnabled = PinStore.isEnabled
    private(set) var signOnRequest: SignOnRequest?
    /// A sign-on that could not be read or answered, shown once.
    var signOnNotice: String?
    /// Transient user-facing message (a toast).
    var notice: String?
    /// Bumped on every lock: views close sheets and forms that belong to the unlocked session.
    private(set) var lockGeneration = 0
    var screenCaptured = false

    var idleMinutes: Int {
        didSet { UserDefaults.standard.set(idleMinutes, forKey: "idle-minutes") }
    }

    private var vaultKey: SymmetricKey?
    private var pinContext: LAContext?
    private var idleLock = IdleLock()
    private var copiedChangeCount: Int?

    var isPaired: Bool { account != nil }
    var needsPushRefresh: Bool { pushState.needsRefresh(paired: isPaired) }

    /// The App Group exchange; tests point it at a temporary directory.
    private let makeHandoff: () -> SignOnHandoff?

    init(account: PairedAccount? = PairingStore.account(), makeHandoff: @escaping () -> SignOnHandoff? = { SignOnHandoff() }) {
        self.account = account
        self.makeHandoff = makeHandoff
        idleMinutes = IdleLock.validatedMinutes(UserDefaults.standard.integer(forKey: "idle-minutes"))
    }

    // MARK: - Lock

    /// One Face ID / passcode prompt releases the vault key; then the PIN, when one is set.
    func unlock() async {
        guard lockState == .locked else { return }
        let generation = lockGeneration
        do {
            let context = try await UserPresence.evaluate(reason: "Unlock your KyAuth codes")
            guard generation == lockGeneration else { return context.invalidate() }
            try TotpVault.ensureKey()
            let key = try TotpVault.key(context: context)
            if pinEnabled {
                pinContext = context
                vaultKey = key
                lockState = .needsPin
            } else {
                context.invalidate()
                finishUnlock(key: key)
            }
        } catch UserPresenceError.cancelled, KeychainError.cancelled {
            return
        } catch {
            notice = error.localizedDescription
        }
    }

    func submitPin(_ pin: String) -> String? {
        guard lockState == .needsPin, let context = pinContext, let key = vaultKey else { return nil }
        let now = Int64(Date().timeIntervalSince1970)
        let state = PinStore.failures
        guard PinFailurePolicy.mayTry(state, now: now) else {
            return "Try again in \(PinFailurePolicy.secondsUntilRetry(state, now: now)) seconds."
        }
        if (try? PinStore.verify(pin, context: context)) == true {
            PinStore.resetFailures()
            context.invalidate()
            pinContext = nil
            finishUnlock(key: key)
            return nil
        }
        let failed = PinFailurePolicy.registerFailure(state, now: now)
        PinStore.saveFailures(failed)
        if PinFailurePolicy.mustWipe(failed) {
            eraseAllData()
            return nil
        }
        let remaining = PinFailurePolicy.attemptsRemaining(failed)
        let wait = PinFailurePolicy.secondsUntilRetry(failed, now: now)
        var message = "Wrong PIN. \(remaining) \(remaining == 1 ? "attempt" : "attempts") left before KyAuth erases its data."
        if wait > 0 { message += " Try again in \(wait) seconds." }
        return message
    }

    private func finishUnlock(key: SymmetricKey) {
        do {
            entries = try TotpVault.standard.load(key: key)
            vaultError = nil
        } catch {
            entries = []
            vaultError = error.localizedDescription
        }
        vaultKey = key
        lockState = .unlocked
        idleLock.reset()
        recordActivity()
    }

    /// Clears codes, the vault key and anything copied, and closes every open form.
    func lock() {
        lockGeneration += 1
        pinContext?.invalidate()
        pinContext = nil
        vaultKey = nil
        entries = []
        vaultError = nil
        lockState = .locked
        idleLock.reset()
        clearCopiedCode()
    }

    func recordActivity() {
        guard lockState != .locked else { return }
        if !idleLock.activity(now: ProcessInfo.processInfo.systemUptime, timeout: TimeInterval(idleMinutes * 60)) {
            lock()
        }
    }

    func checkIdle() {
        guard lockState != .locked else { return }
        if idleLock.expired(now: ProcessInfo.processInfo.systemUptime, timeout: TimeInterval(idleMinutes * 60)) {
            lock()
        }
    }

    // MARK: - TOTP

    func addEntry(_ entry: TotpEntry) throws {
        try saveEntries(entries + [entry])
    }

    func updateEntry(_ entry: TotpEntry) throws {
        try saveEntries(entries.map { $0.id == entry.id ? entry : $0 })
    }

    func deleteEntry(_ entry: TotpEntry) throws {
        try saveEntries(entries.filter { $0.id != entry.id })
    }

    private func saveEntries(_ updated: [TotpEntry]) throws {
        guard let vaultKey, lockState == .unlocked, vaultError == nil else {
            throw VaultError.corrupt
        }
        try TotpVault.standard.save(updated, key: vaultKey)
        entries = updated
    }

    /// Copies a code for this device only; it expires when its period ends or when KyAuth locks.
    func copy(_ code: String, entry: TotpEntry) {
        let remaining = TotpGenerator.secondsRemaining(entry, at: Int64(Date().timeIntervalSince1970))
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: code]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(TimeInterval(remaining))]
        )
        copiedChangeCount = UIPasteboard.general.changeCount
        notice = "Code copied"
    }

    private func clearCopiedCode() {
        if let copiedChangeCount, UIPasteboard.general.changeCount == copiedChangeCount {
            UIPasteboard.general.items = []
        }
        copiedChangeCount = nil
    }

    // MARK: - Pairing

    /// Pairs with KyIdentity. The device key is replaced first, so a failed re-pair leaves the phone
    /// unpaired: its old key is already gone.
    func pair(_ pairing: QrPairing, deviceName: String) async throws {
        guard let pushToken = pushState.latestToken else {
            UIApplication.shared.registerForRemoteNotifications()
            throw PairingError.invalid("KyAuth is still registering with Apple Push. Wait a moment, then try again.")
        }
        guard UserPresence.deviceHasPasscode else { throw UserPresenceError.noPasscode }
        // The old pairing goes first: once its key is replaced it can answer nothing, so any
        // failure from here on must leave the phone unpaired.
        clearPairingState()
        do {
            let publicKey = try DeviceSigningKey.regenerate().base64EncodedString()
            let attestation = await AppAttestor.attest(credential: pairing.credential, publicKey: publicKey)
            let paired = try await PairingClient().register(
                pairing: pairing,
                deviceName: deviceName,
                deviceIdentifier: PairingStore.deviceIdentifier(),
                pushToken: pushToken,
                publicKey: publicKey,
                appAttest: attestation
            )
            try PairingStore.save(paired)
            PushStore.update { $0.registeredToken = pushToken }
            pushState = PushStore.load()
            account = paired
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            DeviceSigningKey.delete()
            throw error
        }
    }

    /// Forgets the pairing on this phone. KyIdentity keeps the device until it is removed there.
    func unpair() {
        DeviceSigningKey.delete()
        clearPairingState()
    }

    private func clearPairingState() {
        PairingStore.clear()
        MfaChallengeStore.clear()
        PushStore.update { $0.registeredToken = nil }
        pushState = PushStore.load()
        account = nil
        pendingChallenge = nil
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    // MARK: - Push

    func didReceiveDeviceToken(_ token: Data) {
        let hex = PushStore.hex(token)
        PushStore.update { $0.latestToken = hex }
        pushState = PushStore.load()
    }

    /// Re-points KyIdentity at the current APNs token, signed by the device key (one prompt).
    func reconnectPush() async {
        guard let account, let token = pushState.latestToken else { return }
        do {
            let issuedAt = Int64(Date().timeIntervalSince1970 * 1000)
            let message = try PushRefreshClient.message(
                serverUrl: account.serverUrl, deviceId: account.deviceId, issuedAtMs: issuedAt, pushToken: token
            )
            let signature = try await signWithDeviceKey(message, reason: "Reconnect KyAuth sign-in requests")
            try await PushRefreshClient().refresh(
                serverUrl: account.serverUrl, deviceId: account.deviceId,
                pushToken: token, issuedAtMs: issuedAt, signature: signature.derRepresentation
            )
            PushStore.update { $0.registeredToken = token }
            pushState = PushStore.load()
            notice = "Sign-in requests reconnected"
        } catch UserPresenceError.cancelled {
            return
        } catch {
            notice = error.localizedDescription
        }
    }

    /// The one receive path for a KyIdentity push: parse against this pairing, save, show.
    func handlePush(_ userInfo: [AnyHashable: Any]) {
        guard userInfo["type"] as? String == "mfa_challenge",
              let challenge = try? MfaPushParser.parse(userInfo, paired: account)
        else { return }
        MfaChallengeStore.save(challenge)
        pendingChallenge = challenge
    }

    /// Picks up a request whose notification the user did not tap.
    func refreshPendingChallenge() async {
        for notification in await UNUserNotificationCenter.current().deliveredNotifications()
            .sorted(by: { $0.date > $1.date }) {
            handlePush(notification.request.content.userInfo)
            if pendingChallenge != nil { break }
        }
        pendingChallenge = MfaChallengeStore.load()
    }

    /// Approve needs the two digits the browser shows; a wrong number is a denial at the server.
    func answer(_ challenge: MfaChallenge, approve: Bool, digits: String) async {
        guard let account, MfaChallengeStore.load()?.challengeId == challenge.challengeId else {
            pendingChallenge = MfaChallengeStore.load()
            return
        }
        if approve && !MfaMessage.isTwoDigits(digits) {
            notice = "Enter the two-digit number shown on the sign-in screen."
            return
        }
        guard let userId = account.userId else {
            notice = "This pairing has no account; pair KyAuth again."
            return
        }
        do {
            let payload = try MfaMessage.payload(
                origin: try MfaMessage.origin(account.serverUrl), userId: userId, deviceId: account.deviceId,
                challengeId: challenge.challengeId, purpose: challenge.purpose,
                expiresAtMs: challenge.expiresAtEpochMs, approve: approve, selectedDigits: approve ? digits : ""
            )
            let signature = try await signWithDeviceKey(
                payload, reason: approve ? "Approve the sign-in request" : "Deny the sign-in request"
            )
            let result = await MfaResponseClient().respond(
                serverUrl: account.serverUrl, challengeId: challenge.challengeId, deviceId: account.deviceId,
                selectedDigits: approve ? digits : "", approve: approve, signature: signature.derRepresentation
            )
            switch result {
            case .success(let approved):
                MfaChallengeStore.clear(challengeId: challenge.challengeId)
                pendingChallenge = MfaChallengeStore.load()
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                notice = approved ? "Sign-in approved" : (approve ? "Sign-in denied: the number did not match" : "Sign-in denied")
            case .error(let message):
                notice = message
            }
        } catch UserPresenceError.cancelled {
            return
        } catch {
            notice = error.localizedDescription
        }
    }

    func dismissExpiredChallenge() {
        pendingChallenge = MfaChallengeStore.load()
    }

    // MARK: - Sign-on handoff

    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "kyauth", url.host?.lowercased() == "signon" else { return }
        let nonce = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "nonce" })?.value ?? ""
        guard let handoff = makeHandoff() else {
            signOnNotice = "Sign-in request expired"
            return
        }
        handoff.sweepStaleRequests()
        retryUnsentResponses()
        do {
            let request = try handoff.take(nonce: nonce, paired: account)
            if signOnRequest == nil {
                signOnRequest = request
            } else {
                // One sign-in at a time. The newer request is answered, not dropped, and KyAuth stays
                // put so the one in progress keeps its prompt; the consumer reads the answer when
                // it is next active.
                deliver(.error("KyAuth is finishing another sign-in. Try again."), nonce: request.nonce, consumer: request.consumer)
            }
        } catch SignOnRefusal.refused(let message, let consumer) {
            finishSignOn(.error(message), nonce: nonce, consumer: consumer)
        } catch {
            signOnNotice = SignOnRefusal.expired.errorDescription
        }
    }

    func approveSignOn() async {
        guard let request = signOnRequest, let account, let userId = account.userId else { return }
        do {
            let now = Int64(Date().timeIntervalSince1970)
            let input = DeviceAssertion.signingInput(
                deviceId: account.deviceId, userId: userId, serverUrl: account.serverUrl,
                clientId: request.clientId, origin: request.origin, now: now, jti: UUID().uuidString.lowercased()
            )
            let signature = try await signWithDeviceKey(
                Data(input.utf8), reason: "Sign in to \(request.consumer.name)"
            )
            let assertion = DeviceAssertion.compact(input, rawSignature: signature.rawRepresentation)
            switch await TokenClient().redeem(serverUrl: account.serverUrl, clientId: request.clientId, assertion: assertion) {
            case .success(let idToken):
                finishSignOn(.ok(idToken: idToken), nonce: request.nonce, consumer: request.consumer)
            case .failure(let message):
                finishSignOn(.error(message), nonce: request.nonce, consumer: request.consumer)
            }
        } catch UserPresenceError.cancelled {
            finishSignOn(.cancelled, nonce: request.nonce, consumer: request.consumer)
        } catch {
            finishSignOn(.error(error.localizedDescription), nonce: request.nonce, consumer: request.consumer)
        }
    }

    func cancelSignOn() {
        guard let request = signOnRequest else { return }
        finishSignOn(.cancelled, nonce: request.nonce, consumer: request.consumer)
    }

    private func finishSignOn(_ response: SignOnResponse, nonce: String, consumer: TrustedConsumers.Consumer) {
        if signOnRequest?.nonce == nonce { signOnRequest = nil }
        guard deliver(response, nonce: nonce, consumer: consumer) else { return }
        if case .error(let message) = response, signOnRequest == nil { signOnNotice = message }
        // Never leave KyAuth while another sign-in is on screen; that consumer reads its answer later.
        if signOnRequest == nil, let url = SignOnHandoff.returnURL(consumer, nonce: nonce) {
            UIApplication.shared.open(url)
        }
    }

    /// Answers that could not be written yet. The request file is already consumed, so the answer is
    /// the consumer's only way out; it is retried until the consumer stops waiting (180 s).
    private var unsentResponses: [String: (response: SignOnResponse, consumer: TrustedConsumers.Consumer, since: Date)] = [:]
    private static let consumerWait: TimeInterval = 180

    var unsentResponseNonces: Set<String> { Set(unsentResponses.keys) }

    /// Writes the answer, or keeps it for `retryUnsentResponses` and says so.
    @discardableResult
    private func deliver(_ response: SignOnResponse, nonce: String, consumer: TrustedConsumers.Consumer) -> Bool {
        do {
            guard let handoff = makeHandoff() else { throw CocoaError(.fileNoSuchFile) }
            try handoff.write(response, nonce: nonce)
            unsentResponses[nonce] = nil
            return true
        } catch {
            if unsentResponses[nonce] == nil {
                unsentResponses[nonce] = (response, consumer, Date())
            }
            notice = "Could not hand the sign-in back to \(consumer.name). KyAuth will try again."
            return false
        }
    }

    func retryUnsentResponses(now: Date = Date()) {
        for (nonce, pending) in unsentResponses {
            if now.timeIntervalSince(pending.since) > Self.consumerWait {
                unsentResponses[nonce] = nil
            } else if deliver(pending.response, nonce: nonce, consumer: pending.consumer), signOnRequest == nil,
                      let url = SignOnHandoff.returnURL(pending.consumer, nonce: nonce) {
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Settings

    func setPin(_ pin: String) throws {
        try PinStore.set(pin)
        pinEnabled = true
    }

    func removePin() {
        PinStore.remove()
        pinEnabled = false
    }

    func eraseAllData() {
        lock()
        LocalWipe.eraseAll()
        account = nil
        pendingChallenge = nil
        pushState = PushState()
        pinEnabled = false
        idleMinutes = IdleLock.defaultMinutes
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Device key

    /// Exactly one Face ID / passcode prompt per signature. Works while the vault is locked.
    private func signWithDeviceKey(_ message: Data, reason: String) async throws -> P256.Signing.ECDSASignature {
        let context = try await UserPresence.evaluate(reason: reason)
        defer { context.invalidate() }
        return try DeviceSigningKey.sign(message, context: context)
    }
}
