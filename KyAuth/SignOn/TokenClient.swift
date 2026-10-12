import Foundation

enum TokenResult: Equatable, CustomStringConvertible {
    case success(idToken: String)
    case failure(String)

    var description: String {
        switch self {
        case .success: "success(redacted)"
        case .failure(let message): "failure(\(message))"
        }
    }
}

/// Redeems a device assertion at KyIdentity's token endpoint. The ID token is returned, never stored.
struct TokenClient {
    var http = HTTPClient.shared

    func redeem(serverUrl: String, clientId: String, assertion: String) async -> TokenResult {
        guard let url = try? PairingEndpoint.tokenUrl(serverUrl) else {
            return .failure("The paired server address is not valid.")
        }
        do {
            let response = try await http.send(
                "POST", url, body: Data(Self.formBody(clientId: clientId, assertion: assertion).utf8),
                contentType: "application/x-www-form-urlencoded"
            )
            return Self.parse(status: response.status, json: response.json)
        } catch {
            return .failure("Could not reach KyIdentity. Check the connection and try again.")
        }
    }

    static func formBody(clientId: String, assertion: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return [
            ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            ("assertion", assertion),
            ("client_id", clientId),
        ].map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }

    static func parse(status: Int, json: [String: Any]) -> TokenResult {
        if status == 429 { return .failure("KyIdentity is busy. Try again in a minute.") }
        guard (200..<300).contains(status) else {
            switch json["error_description"] as? String {
            case "device_signon_disabled":
                return .failure("Sign-in from this phone is turned off. Turn it on for this device on the KyIdentity devices page, then try again.")
            case "signon_not_permitted":
                return .failure("This account cannot sign in to apps from this phone right now. Use web sign-in.")
            default:
                return .failure("KyIdentity refused the sign-in (\(status)).")
            }
        }
        guard let idToken = (json["id_token"] as? String)?.trimmedNonBlank else {
            return .failure("KyIdentity returned no identity token.")
        }
        return .success(idToken: idToken)
    }
}
