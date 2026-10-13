import Foundation

struct MfaChallenge: Codable, Equatable, Identifiable {
    let challengeId: String
    let serverUrl: String
    var username: String?
    let purpose: String
    let expiresAtEpochMs: Int64

    var id: String { challengeId }

    var purposeText: String { purpose == "step_up" ? "Confirm a sensitive action" : "Sign in" }

    func isExpired(now: Date = Date()) -> Bool {
        Int64(now.timeIntervalSince1970 * 1000) >= expiresAtEpochMs
    }

    func secondsRemaining(now: Date = Date()) -> Int64 {
        max(0, (expiresAtEpochMs - Int64(now.timeIntervalSince1970 * 1000) + 999) / 1000)
    }
}

enum MfaMessage {
    // Wire contract: must equal what KyIdentity's internal/mfa PushResponseMessage builds.
    private static let prefix = "kyidentity-push-v2"
    static let purposes: Set<String> = ["login", "step_up"]

    /// scheme://host[:port], lowercased, default port dropped; the same rule KyIdentity uses.
    static func origin(_ serverUrl: String) throws -> String {
        guard let url = URLComponents(string: serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty
        else {
            throw PairingError.invalid("Server URL has no origin")
        }
        let defaultPort = (scheme == "https" && url.port == 443) || (scheme == "http" && url.port == 80)
        if let port = url.port, !defaultPort { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }

    /// The exact bytes the device key signs to answer a challenge. Deny signs empty digits.
    static func payload(
        origin: String, userId: String, deviceId: String, challengeId: String,
        purpose: String, expiresAtMs: Int64, approve: Bool, selectedDigits: String
    ) throws -> Data {
        guard purposes.contains(purpose) else { throw PairingError.invalid("Unknown push purpose") }
        for field in [origin, userId, deviceId, challengeId] where field.isEmpty || field.contains("|") {
            throw PairingError.invalid("Invalid push binding field")
        }
        guard !selectedDigits.contains("|") else { throw PairingError.invalid("Invalid digits") }
        return Data([
            prefix, origin, userId, deviceId, challengeId, purpose, String(expiresAtMs),
            approve ? "approve" : "deny", selectedDigits,
        ].joined(separator: "|").utf8)
    }

    static func isTwoDigits(_ value: String) -> Bool {
        value.count == 2 && value.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

/// Parses a KyIdentity push (APNs custom keys, all strings) into a challenge for this pairing only.
enum MfaPushParser {
    static let maxExpiresAfterMs: Int64 = 10 * 60 * 1000

    /// A push for another device or account, an unknown purpose, or an expiry that is absent, past or
    /// more than ten minutes ahead is refused, never defaulted or clamped. A `serverUrl` in the
    /// payload is ignored: answers only ever go to the paired server. So is any match or decoy
    /// number: the phone never holds the answer, the user types the number the browser shows.
    static func parse(_ data: [AnyHashable: Any], paired: PairedAccount?, now: Date = Date()) throws -> MfaChallenge {
        guard let paired, !paired.serverUrl.isBlank, !paired.deviceId.isBlank else {
            throw PairingError.invalid("KyAuth is not paired with a server")
        }
        guard let userId = paired.userId, !userId.isBlank else {
            throw PairingError.invalid("This pairing has no account; pair KyAuth again")
        }
        func value(_ keys: String...) -> String? {
            keys.lazy.compactMap { (data[$0] as? String)?.trimmedNonBlank }.first
        }
        guard value("deviceId") == paired.deviceId else { throw PairingError.invalid("Push is for another device") }
        guard value("deviceUserId") == userId else { throw PairingError.invalid("Push is for another account") }
        guard let challengeId = value("challengeId", "challenge_id", "id") else {
            throw PairingError.invalid("MFA push payload missing challengeId")
        }
        guard let purpose = value("purpose"), MfaMessage.purposes.contains(purpose) else {
            throw PairingError.invalid("Unknown push purpose")
        }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        guard let expiresAt = value("expiresAtEpochMs").flatMap({ Int64($0) }), expiresAt > nowMs else {
            throw PairingError.invalid("Challenge has expired or has no expiry")
        }
        guard expiresAt <= nowMs + maxExpiresAfterMs else { throw PairingError.invalid("Challenge expiry is too far ahead") }

        return MfaChallenge(
            challengeId: challengeId,
            serverUrl: paired.serverUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            username: value("username", "user"),
            purpose: purpose,
            expiresAtEpochMs: expiresAt
        )
    }
}

/// The one pending sign-in request. Clearing by ID keeps a newer request alive past a late answer.
enum MfaChallengeStore {
    private static let key = "mfa-challenge"

    static func save(_ challenge: MfaChallenge) {
        try? KeychainCodable.save(challenge, key)
    }

    static func load(now: Date = Date()) -> MfaChallenge? {
        guard let challenge = KeychainCodable.load(MfaChallenge.self, key) else { return nil }
        if challenge.isExpired(now: now) {
            clear()
            return nil
        }
        return challenge
    }

    static func clear() {
        Keychain.delete(key)
    }

    static func clear(challengeId: String) {
        if load()?.challengeId == challengeId { clear() }
    }
}
