import CryptoKit
import Foundation

/// Tells KyIdentity where to push this device now, signed by the device key.
struct PushRefreshClient {
    // Wire contract: must equal what KyIdentity verifies for a push-token refresh.
    private static let prefix = "kyidentity-push-token-v2"
    /// KyIdentity's relay transport. It covers APNs: the relay routes by the device's platform.
    static let transport = "fcm"

    var http = HTTPClient.shared

    func refresh(serverUrl: String, deviceId: String, pushToken: String, issuedAtMs: Int64, signature: Data) async throws {
        let url = try PairingEndpoint.pushTokenUrl(serverUrl, deviceId: deviceId)
        let body = try JSONSerialization.data(withJSONObject: Self.requestBody(
            pushToken: pushToken, issuedAtMs: issuedAtMs, signature: signature
        ), options: [.sortedKeys])
        let response = try await http.send("PUT", url, body: body)
        guard response.isSuccess else {
            throw PairingError.invalid(response.errorText ?? "Reconnecting sign-in requests failed (\(response.status))")
        }
    }

    /// The exact bytes the device key signs to move this device's pushes. The relay transport has no
    /// Web Push keys, so the last two fields are empty.
    static func message(serverUrl: String, deviceId: String, issuedAtMs: Int64, pushToken: String) throws -> Data {
        let fields = [
            prefix, try MfaMessage.origin(serverUrl), deviceId, String(issuedAtMs), transport,
            sha256Hex(pushToken), "", "",
        ]
        guard !deviceId.isEmpty, !fields.contains(where: { $0.contains("|") }) else {
            throw PairingError.invalid("Invalid push refresh field")
        }
        return Data(fields.joined(separator: "|").utf8)
    }

    static func requestBody(pushToken: String, issuedAtMs: Int64, signature: Data) -> [String: Any] {
        [
            "pushToken": pushToken,
            "pushTransport": transport,
            "issuedAt": issuedAtMs,
            "signature": signature.base64EncodedString(),
        ]
    }

    static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
