import CryptoKit
import Foundation

/// KyAuth pairing proof v1, QR pairing only: the token never crosses the wire. Both sides MAC the
/// exact bytes they send with K = SHA-256(token), which KyIdentity already stores as the token hash.
/// Wire contract shared with KyIdentity-server and KyAuth Android; vectors in `PairingProofTests`.
struct PairingProof {
    static let header = "KyIdentity-Pairing-Proof"

    private let key: SymmetricKey
    private let origin: String

    /// Nil for PIN pairing, which stays trust on first use: a 6-digit PIN falls to an offline
    /// search of a MAC.
    init?(_ pairing: QrPairing) throws {
        guard let key = pairing.proofKey else { return nil }
        self.key = SymmetricKey(data: key)
        origin = try MfaMessage.origin(pairing.serverUrl)
    }

    /// The request header value over the exact body bytes sent.
    func request(_ body: Data) -> String {
        Base64URL.encode(mac(Data("kyidentity-pair/1\n\(origin)\n".utf8) + body))
    }

    /// Whether `proof` is KyIdentity's MAC over this reply to this request, compared in constant time.
    func acceptsReply(_ proof: String?, request: Data, response: Data) -> Bool {
        guard let proof, let code = Base64URL.decode(proof) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: replyMessage(request, response), using: key)
    }

    static func requestHash(_ body: Data) -> String {
        Base64URL.encode(Data(SHA256.hash(data: body)))
    }

    private func replyMessage(_ request: Data, _ response: Data) -> Data {
        Data("kyidentity-pair-reply/1\n\(origin)\n\(Self.requestHash(request))\n".utf8) + response
    }

    private func mac(_ message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
    }
}
