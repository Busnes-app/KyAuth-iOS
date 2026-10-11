import Foundation

struct PairedAccount: Codable, Equatable {
    var serverUrl: String
    var deviceId: String
    var deviceName: String
    var username: String?
    var userId: String?
    var canSignOn: Bool = false
    /// `none` or `appattest`, as KyIdentity graded the pairing.
    var attestedLevel: String = "none"
    /// An `AttestationReason` value; empty when attested.
    var attestationReason: String = ""
}

/// The pairing record and this install's stable device identifier. KyIdentity upserts a
/// re-pairing on (user, deviceIdentifier), so the identifier must survive re-pairing.
enum PairingStore {
    private static let accountKey = "pairing"
    private static let installationKey = "installation-id"

    static func deviceIdentifier() -> String {
        if let data = try? Keychain.get(installationKey), let id = String(data: data, encoding: .utf8) {
            return id
        }
        let id = UUID().uuidString.lowercased()
        try? Keychain.set(Data(id.utf8), for: installationKey)
        return id
    }

    static func account() -> PairedAccount? {
        KeychainCodable.load(PairedAccount.self, accountKey)
    }

    static func save(_ account: PairedAccount) throws {
        try KeychainCodable.save(account, accountKey)
    }

    static func clear() {
        Keychain.delete(accountKey)
    }
}
