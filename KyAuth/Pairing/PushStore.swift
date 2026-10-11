import Foundation

/// The APNs device token Apple last gave KyAuth, and the one KyIdentity last acknowledged.
/// They differ after a token rotation; Vault then offers "Reconnect sign-in requests".
struct PushState: Codable, Equatable {
    var latestToken: String?
    var registeredToken: String?

    func needsRefresh(paired: Bool) -> Bool {
        paired && latestToken != nil && latestToken != registeredToken
    }
}

enum PushStore {
    private static let key = "push"

    static func load() -> PushState {
        KeychainCodable.load(PushState.self, key) ?? PushState()
    }

    static func update(_ change: (inout PushState) -> Void) {
        var state = load()
        change(&state)
        try? KeychainCodable.save(state, key)
    }

    static func clear() {
        Keychain.delete(key)
    }

    /// APNs hands over raw bytes; KyIdentity and the relay expect lowercase hex.
    static func hex(_ deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }
}
