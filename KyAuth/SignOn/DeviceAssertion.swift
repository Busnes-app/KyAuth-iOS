import Foundation

/// Builds the RFC 7523 assertion KyIdentity's jwt-bearer grant verifies. Pure: the caller signs
/// `signingInput` with the device key and passes the raw 64-byte `r||s` signature to `compact`.
enum DeviceAssertion {
    static let ttlSeconds: Int64 = 120
    private static let maxRelayLength = 256

    static func isValidClientId(_ value: String?) -> Bool {
        guard let value, (1...128).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._:-".unicodeScalars.contains($0))
        }
    }

    /// The relay a consumer connects to, as `https://host[:port]`; nil unless it is plain HTTPS.
    static func relayOrigin(_ raw: String?) -> String? {
        guard let raw, raw.count <= maxRelayLength,
              let url = URLComponents(string: raw),
              url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), !host.isEmpty,
              host.unicodeScalars.allSatisfy(\.isASCII)
        else { return nil }
        if let port = url.port {
            guard (1...65535).contains(port) else { return nil }
            if port != 443 { return "https://\(host):\(port)" }
        }
        return "https://\(host)"
    }

    static func signingInput(
        deviceId: String, userId: String, serverUrl: String, clientId: String,
        origin: String, now: Int64, jti: String
    ) -> String {
        let header: [String: Any] = ["alg": "ES256", "typ": "JWT", "kid": deviceId]
        let claims: [String: Any] = [
            "iss": "device:\(deviceId)",
            "sub": userId,
            "aud": serverUrl.trimmingTrailingSlashes() + "/oauth/token",
            "client_id": clientId,
            "iat": now,
            "exp": now + ttlSeconds,
            "jti": jti,
            "origin": origin,
        ]
        return base64url(json(header)) + "." + base64url(json(claims))
    }

    static func compact(_ signingInput: String, rawSignature: Data) -> String {
        signingInput + "." + base64url(rawSignature)
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }
}
