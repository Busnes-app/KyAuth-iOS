import Foundation

private let levels: Set<String> = ["none", "appattest"]

/// Registers this phone with KyIdentity. The request always names `platform: "ios"`: an omitted
/// platform is stored as Android, and its pushes would go to FCM with an APNs token. It always sends
/// the push keys, so KyIdentity seals every push to this phone. QR pairing sends pairing proof v1
/// (`PairingProof`) instead of the token and needs a KyIdentity that supports it.
struct PairingClient {
    static let unverifiedReply = "The server's pairing reply could not be verified."

    var http = HTTPClient.shared

    func register(
        pairing: QrPairing,
        deviceName: String,
        deviceIdentifier: String,
        pushToken: String,
        pushKeys: PushKeys,
        publicKey: String,
        appAttest: AppAttestation?
    ) async throws -> PairedAccount {
        let endpoint = try PairingEndpoint.validatedRegistrationUrl(pairing.serverUrl, pairing.registrationUrl)
        let proof = try PairingProof(pairing)
        // Encoded once: the proof covers exactly these bytes.
        let body = try HTTPClient.encodeJSON(Self.requestBody(
            pairing: pairing, deviceName: deviceName, deviceIdentifier: deviceIdentifier,
            pushToken: pushToken, pushKeys: pushKeys, publicKey: publicKey, appAttest: appAttest
        ))
        let headers = proof.map { [PairingProof.header: $0.request(body)] } ?? [:]
        let response = try await http.send("POST", endpoint, body: body, headers: headers)
        let json = try Self.acceptedReply(response, proof: proof, request: body)
        return try Self.parseRegistration(json, pairing: pairing, deviceName: deviceName, attested: appAttest != nil)
    }

    /// The reply's JSON, read only after a proof pairing's reply proof checks out.
    static func acceptedReply(_ response: HTTPResponse, proof: PairingProof?, request: Data) throws -> [String: Any] {
        guard response.isSuccess else {
            throw PairingError.invalid(response.errorText ?? "Pairing failed (\(response.status))")
        }
        if let proof, !proof.acceptsReply(response.headers[PairingProof.header.lowercased()], request: request, response: response.body) {
            throw PairingError.invalid(unverifiedReply)
        }
        guard response.json["success"] as? Bool == true else {
            throw PairingError.invalid(response.errorText ?? "Pairing failed (\(response.status))")
        }
        return response.json
    }

    static func requestBody(
        pairing: QrPairing,
        deviceName: String,
        deviceIdentifier: String,
        pushToken: String,
        pushKeys: PushKeys,
        publicKey: String,
        appAttest: AppAttestation?
    ) -> [String: Any] {
        var body: [String: Any] = [
            "deviceName": deviceName.trimmingCharacters(in: .whitespacesAndNewlines),
            "deviceIdentifier": deviceIdentifier,
            "platform": "ios",
            "publicKey": publicKey,
            "pushToken": pushToken,
            "pushP256dh": pushKeys.p256dh,
            "pushAuth": pushKeys.authSecret,
        ]
        // The token never crosses the wire; a proof pairing sends no PIN either.
        if pairing.proofKey == nil, let pin = pairing.pinCode, !pin.isBlank { body["pinCode"] = pin }
        if let userId = pairing.userId, !userId.isBlank { body["userId"] = userId }
        if let appAttest {
            body["appAttest"] = ["keyId": appAttest.keyId, "attestation": appAttest.attestation]
        }
        return body
    }

    static func parseRegistration(
        _ response: [String: Any],
        pairing: QrPairing,
        deviceName: String,
        attested: Bool
    ) throws -> PairedAccount {
        guard let deviceId = (response["deviceId"] as? String)?.trimmedNonBlank else {
            throw PairingError.invalid("KyIdentity did not return a device ID")
        }
        let device = response["device"] as? [String: Any]
        let reported = device?["attestedLevel"] as? String
        let level = reported.flatMap { levels.contains($0) ? $0 : nil } ?? "none"
        return PairedAccount(
            serverUrl: pairing.serverUrl.trimmingTrailingSlashes(),
            deviceId: deviceId,
            deviceName: deviceName.trimmingCharacters(in: .whitespacesAndNewlines),
            username: pairing.username,
            userId: (device?["userId"] as? String)?.trimmedNonBlank ?? pairing.userId,
            canSignOn: device?["canSignOn"] as? Bool ?? false,
            attestedLevel: level,
            attestationReason: AttestationReason.classify(
                level: level, serverReportedLevel: reported != nil, attested: attested
            )
        )
    }
}
