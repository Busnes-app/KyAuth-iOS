import Foundation

/// App Store review demo for an unpaired install. Everything here is fixed or in memory: no network,
/// no vault, no Keychain, no settings written. `.invalid` (RFC 2606) can never resolve.
enum DemoMode {
    static let pushInterval: TimeInterval = 15
    static let firstPushDelay: TimeInterval = 3
    static let pushLifetimeMs: Int64 = 60_000
    static let serverUrl = "https://demo.kyidentity.invalid"
    static let username = "demo@example.com"

    static func entries() -> [TotpEntry] {
        [
            try! TotpEntry(title: "Example Mail", secretBase32: "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP", url: "https://mail.example.com", id: "demo-mail"),
            try! TotpEntry(title: "Example Cloud", secretBase32: "KRSXG5CTMVRXEZLUKRSXG5CTMVRXEZLU", url: "https://cloud.example.com", id: "demo-cloud"),
            try! TotpEntry(title: "Example Bank", secretBase32: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", notes: "Demo account", id: "demo-bank"),
        ]
    }

    /// A sign-in request shaped like a KyIdentity push: no answer in it.
    static func challenge(nowMs: Int64) -> MfaChallenge {
        MfaChallenge(
            challengeId: "demo-\(UUID().uuidString.lowercased())",
            serverUrl: serverUrl,
            username: username,
            purpose: "login",
            expiresAtEpochMs: nowMs + pushLifetimeMs
        )
    }

    /// The number a browser would show for the request. A real phone never knows it; the demo has
    /// no browser, so the request card tells the reviewer what to type.
    static func browserDigits(using generator: inout some RandomNumberGenerator) -> String {
        String(Int.random(in: 10...99, using: &generator))
    }

    /// What the server would have decided, as the toast says it.
    static func result(_ challenge: MfaChallenge, approve: Bool, digits: String, browserDigits: String, now: Date = Date()) -> String {
        if challenge.isExpired(now: now) { return "Sign-in request expired" }
        if !approve { return "Sign-in denied" }
        return digits == browserDigits ? "Sign-in approved" : "Sign-in denied: the number did not match"
    }
}
