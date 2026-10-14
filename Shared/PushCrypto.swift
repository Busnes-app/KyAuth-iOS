import CryptoKit
import Foundation

struct PushPayloadError: Error {}

/// This pairing's RFC 8291 Web Push keys, made on the phone at pairing. KyIdentity gets the public
/// key and the auth secret and seals every push to them, so APNs and the relay see only ciphertext.
struct PushKeys {
    let privateKey: P256.KeyAgreement.PrivateKey
    let auth: Data

    static func generate() -> PushKeys {
        PushKeys(privateKey: P256.KeyAgreement.PrivateKey(), auth: SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) })
    }

    init(privateKey: P256.KeyAgreement.PrivateKey, auth: Data) {
        self.privateKey = privateKey
        self.auth = auth
    }

    /// The Keychain form: the 32-byte private scalar, then the 16-byte auth secret.
    init(stored: Data) throws {
        guard stored.count == 48 else { throw PushPayloadError() }
        privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: stored.prefix(32))
        auth = Data(stored.suffix(16))
    }

    var stored: Data { privateKey.rawRepresentation + auth }

    /// `pushP256dh` and `pushAuth`: base64url without padding of the uncompressed point and the secret.
    var p256dh: String { Base64URL.encode(privateKey.publicKey.x963Representation) }
    var authSecret: String { Base64URL.encode(auth) }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        let base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4))
    }
}

enum WebPush {
    /// Opens an RFC 8291 aes128gcm body: RFC 8188 header (salt, record size, sender key), one record.
    static func decrypt(_ message: Data, keys: PushKeys) throws -> Data {
        let body = Data(message)
        guard body.count >= 86 + 17, body[20] == 65 else { throw PushPayloadError() }
        let salt = body[0..<16]
        let recordSize = body[16..<20].reduce(0) { $0 << 8 | Int($1) }
        let senderKey = body[21..<86]
        let record = body[86...]
        guard recordSize >= 18, record.count <= recordSize else { throw PushPayloadError() } // one record only

        let shared = try keys.privateKey.sharedSecretFromKeyAgreement(
            with: P256.KeyAgreement.PublicKey(x963Representation: senderKey)
        )
        let ikm = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: keys.auth,
            sharedInfo: Data("WebPush: info\0".utf8) + keys.privateKey.publicKey.x963Representation + senderKey,
            outputByteCount: 32
        )
        func derive(_ info: String, _ count: Int) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data(info.utf8), outputByteCount: count)
        }
        let nonce = derive("Content-Encoding: nonce\0", 12).withUnsafeBytes { Data($0) }
        let padded = try AES.GCM.open(
            AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: record.dropLast(16), tag: record.suffix(16)),
            using: derive("Content-Encoding: aes128gcm\0", 16)
        )
        // Zero padding follows the last-record delimiter 0x02.
        guard let end = padded.lastIndex(where: { $0 != 0 }), padded[end] == 2 else { throw PushPayloadError() }
        return Data(padded[padded.startIndex..<end])
    }
}

enum PushPayload {
    /// The challenge fields of a KyIdentity push. A sealed push (`kyauth`) needs this pairing's keys.
    /// A plaintext push is accepted only by a pairing without keys, made before KyAuth sent them:
    /// otherwise the relay could inject requests.
    static func fields(_ userInfo: [AnyHashable: Any], keys: PushKeys?) throws -> [AnyHashable: Any] {
        guard let sealed = userInfo["kyauth"] as? String else {
            guard keys == nil else { throw PushPayloadError() }
            return userInfo
        }
        guard let keys, let body = Base64URL.decode(sealed),
              let fields = try JSONSerialization.jsonObject(with: WebPush.decrypt(body, keys: keys)) as? [String: String]
        else { throw PushPayloadError() }
        return fields
    }

    /// Fixed alert text. Nothing from the payload is ever shown, not even the username.
    static let alertBody = "Open KyAuth to review."

    static func alertTitle(purpose: String?) -> String {
        purpose == "step_up" ? "Confirm a sensitive action" : "Sign-in request"
    }
}
