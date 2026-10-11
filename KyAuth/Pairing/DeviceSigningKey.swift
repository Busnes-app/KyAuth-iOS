import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum DeviceKeyError: LocalizedError {
    case unavailable
    case missing

    var errorDescription: String? {
        switch self {
        case .unavailable: "This device has no Secure Enclave, so KyAuth cannot pair it."
        case .missing: "This phone's device key is missing. Pair KyAuth again."
        }
    }
}

/// The P-256 key KyIdentity knows this device by. It lives in the Secure Enclave, cannot be
/// exported, and every signature needs a user-presence check (`.privateKeyUsage` + `.userPresence`).
/// The Keychain holds only the enclave's wrapped handle, which is useless on any other device.
enum DeviceSigningKey {
    private static let account = "device-signing-key-v1"

    private struct Stored: Codable {
        /// `enclave` in production; `software` only in the simulator, which has no Secure Enclave.
        let kind: String
        let data: Data
    }

    /// Deletes any old key and creates a fresh one for a new pairing. Returns the SPKI DER.
    static func regenerate() throws -> Data {
        delete()
        if SecureEnclave.isAvailable {
            var error: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.privateKeyUsage, .userPresence], &error
            ) else {
                throw error!.takeRetainedValue() as Error
            }
            let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
            try KeychainCodable.save(Stored(kind: "enclave", data: key.dataRepresentation), account)
            return key.publicKey.derRepresentation
        }
        #if targetEnvironment(simulator)
        let key = P256.Signing.PrivateKey()
        try KeychainCodable.save(Stored(kind: "software", data: key.rawRepresentation), account)
        return key.publicKey.derRepresentation
        #else
        throw DeviceKeyError.unavailable
        #endif
    }

    static var exists: Bool { Keychain.exists(account) }

    /// Signs [message] (SHA-256 inside). [context] must already be evaluated by `UserPresence`.
    static func sign(_ message: Data, context: LAContext) throws -> P256.Signing.ECDSASignature {
        guard let stored = KeychainCodable.load(Stored.self, account) else { throw DeviceKeyError.missing }
        switch stored.kind {
        case "enclave":
            let key = try SecureEnclave.P256.Signing.PrivateKey(
                dataRepresentation: stored.data, authenticationContext: context
            )
            return try key.signature(for: message)
        default:
            #if targetEnvironment(simulator)
            return try P256.Signing.PrivateKey(rawRepresentation: stored.data).signature(for: message)
            #else
            throw DeviceKeyError.missing
            #endif
        }
    }

    static func delete() {
        Keychain.delete(account)
    }
}
