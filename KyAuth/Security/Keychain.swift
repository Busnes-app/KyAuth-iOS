import Foundation
import LocalAuthentication
import Security

enum KeychainError: LocalizedError {
    case status(OSStatus)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled: "Authentication was cancelled."
        case .status(let status): (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }
}

/// Generic-password items under one service, never synced and never restored to another device.
/// Keychain items outlive an uninstall, so `LocalWipe` clears them on the first launch of a new install.
enum Keychain {
    static let service = "org.kysecurity.authenticator"

    /// Readable after first unlock: push handling may need the pairing before the app is opened.
    static func set(_ data: Data, for account: String) throws {
        delete(account)
        var query = baseQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    /// Readable only with a user-presence check (Face ID, Touch ID or the device passcode) and only
    /// while a passcode is set: removing the passcode destroys the item.
    static func setProtected(_ data: Data, for account: String) throws {
        delete(account)
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error
        ) else {
            throw error!.takeRetainedValue() as Error
        }
        var query = baseQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    /// Reads an item. A protected item needs `context` already evaluated, so no second prompt appears.
    static func get(_ account: String, context: LAContext? = nil) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context ?? noInteraction()
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        case errSecUserCanceled: throw KeychainError.cancelled
        default: throw KeychainError.status(status)
        }
    }

    static func exists(_ account: String) -> Bool {
        var query = baseQuery(account)
        query[kSecUseAuthenticationContext as String] = noInteraction()
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    /// Every item KyAuth wrote, whatever its account.
    static func deleteAll() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
    }

    /// A context that fails instead of prompting.
    private static func noInteraction() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }
}

/// Codable values stored as unprotected Keychain items.
enum KeychainCodable {
    static func load<T: Decodable>(_ type: T.Type, _ account: String) -> T? {
        guard let data = try? Keychain.get(account) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ account: String) throws {
        try Keychain.set(try JSONEncoder().encode(value), for: account)
    }
}
