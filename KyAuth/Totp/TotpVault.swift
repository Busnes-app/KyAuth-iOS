import CryptoKit
import Foundation
import LocalAuthentication

enum VaultError: LocalizedError {
    case corrupt
    case keyMissing

    var errorDescription: String? {
        switch self {
        case .corrupt: "The TOTP vault could not be opened."
        case .keyMissing: "The TOTP vault key is gone, usually because the device passcode was removed. Erase KyAuth's data to start again."
        }
    }
}

/// TOTP entries in one AES-256-GCM file. The 32-byte random key is a Keychain item that only a
/// Face ID, Touch ID or passcode check releases, and that iOS destroys if the passcode is removed.
/// The file is excluded from backup and never exported or synced: losing the phone loses its entries.
struct TotpVault {
    private static let keyAccount = "totp-vault-key"
    private static let aad = Data("kyauth-totp-vault-v1".utf8)

    let file: URL

    static let standard = TotpVault(file: URL.applicationSupportDirectory.appendingPathComponent("totp_vault.bin"))

    /// Creates the key on first use. Writing a protected item needs no prompt.
    static func ensureKey() throws {
        guard !Keychain.exists(keyAccount) else { return }
        try Keychain.setProtected(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }, for: keyAccount)
    }

    /// The key, released by an evaluated user-presence context.
    static func key(context: LAContext) throws -> SymmetricKey {
        guard let data = try Keychain.get(keyAccount, context: context) else { throw VaultError.keyMissing }
        return SymmetricKey(data: data)
    }

    static func deleteKey() {
        Keychain.delete(keyAccount)
    }

    /// False until the first save: nothing to unlock yet.
    var exists: Bool { FileManager.default.fileExists(atPath: file.path) }

    /// Empty only when no vault exists yet. An unreadable or empty file is an error, which keeps
    /// saving disabled so a write cannot replace entries that failed to load.
    func load(key: SymmetricKey) throws -> [TotpEntry] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let sealed: Data
        do {
            sealed = try Data(contentsOf: file)
        } catch {
            throw VaultError.corrupt
        }
        guard !sealed.isEmpty else { throw VaultError.corrupt }
        return try Self.open(sealed, key: key)
    }

    func save(_ entries: [TotpEntry], key: SymmetricKey) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.seal(entries, key: key).write(to: file, options: [.atomic, .completeFileProtection])
        var url = file
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    func delete() {
        try? FileManager.default.removeItem(at: file)
    }

    static func seal(_ entries: [TotpEntry], key: SymmetricKey) throws -> Data {
        let plain = try JSONEncoder().encode(Contents(entries: entries))
        guard let combined = try AES.GCM.seal(plain, using: key, authenticating: aad).combined else {
            throw VaultError.corrupt
        }
        return combined
    }

    static func open(_ sealed: Data, key: SymmetricKey) throws -> [TotpEntry] {
        do {
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: aad)
            return try JSONDecoder().decode(Contents.self, from: plain).entries
        } catch {
            throw VaultError.corrupt
        }
    }

    private struct Contents: Codable {
        var v = 1
        var entries: [TotpEntry]
    }
}
