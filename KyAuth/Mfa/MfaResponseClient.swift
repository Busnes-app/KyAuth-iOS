import Foundation

enum MfaResponseResult: Equatable {
    case success(approved: Bool)
    case error(String)
}

struct MfaResponseClient {
    var http = HTTPClient.shared

    func respond(
        serverUrl: String, challengeId: String, deviceId: String,
        selectedDigits: String, approve: Bool, signature: Data
    ) async -> MfaResponseResult {
        do {
            let url = try PairingEndpoint.mfaRespondUrl(serverUrl)
            let response = try await http.postJSON(url, [
                "challengeId": challengeId,
                "deviceId": deviceId,
                "selectedDigits": selectedDigits,
                "approve": approve,
                "signature": signature.base64EncodedString(),
            ])
            return Self.parse(status: response.status, json: response.json, errorText: response.errorText, challengeId: challengeId)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// A 2xx with no decision in it is a protocol error, not an approval. Reporting back whatever
    /// was asked for would turn a broken or hostile server into a silent "approved".
    static func parse(status: Int, json: [String: Any], errorText: String?, challengeId: String) -> MfaResponseResult {
        guard (200..<300).contains(status) else {
            return .error(errorText ?? "Push response failed (\(status))")
        }
        if let echoed = (json["challengeId"] as? String)?.trimmedNonBlank, echoed != challengeId {
            return .error("Server answered a different challenge")
        }
        if let approved = json["approved"] as? Bool { return .success(approved: approved) }
        if let success = json["success"] as? Bool { return .success(approved: success) }
        return .error("Server did not report a decision")
    }
}
