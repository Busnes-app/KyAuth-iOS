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
            try! TotpEntry(title: "Example Mail", secretBase32: "JBSWY3DPEHPK3PXP", url: "https://mail.example.com", id: "demo-mail"),
            try! TotpEntry(title: "Example Cloud", secretBase32: "KRSXG5CTMVRXEZLU", url: "https://cloud.example.com", id: "demo-cloud"),
            try! TotpEntry(title: "Example Bank", secretBase32: "GEZDGNBVGY3TQOJQ", notes: "Demo account", id: "demo-bank"),
        ]
    }

    /// A sign-in request offering the match among three decoys.
    static func challenge(nowMs: Int64, using generator: inout some RandomNumberGenerator) -> MfaChallenge {
        let numbers = (10...99).shuffled(using: &generator).prefix(4).map(String.init)
        return MfaChallenge(
            challengeId: "demo-\(UUID().uuidString.lowercased())",
            matchDigits: numbers[0],
            decoyDigits: Array(numbers.dropFirst()),
            serverUrl: serverUrl,
            username: username,
            purpose: "login",
            expiresAtEpochMs: nowMs + pushLifetimeMs
        )
    }

    /// What the server would have decided, as the toast says it.
    static func result(_ challenge: MfaChallenge, approve: Bool, digits: String, now: Date = Date()) -> String {
        if challenge.isExpired(now: now) { return "Sign-in request expired" }
        if !approve { return "Sign-in denied" }
        return digits == challenge.matchDigits ? "Sign-in approved" : "Sign-in denied: the number did not match"
    }
}
