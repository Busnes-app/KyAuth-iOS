import Foundation

private let levels: Set<String> = ["none", "appattest"]

/// Registers this phone with KyIdentity. The request always names `platform: "ios"`: an omitted
/// platform is stored as Android, and its pushes would go to FCM with an APNs token. It always sends
/// the push keys, so KyIdentity seals every push to this phone.
struct PairingClient {
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
        let request = Self.requestBody(
            pairing: pairing, deviceName: deviceName, deviceIdentifier: deviceIdentifier,
            pushToken: pushToken, pushKeys: pushKeys, publicKey: publicKey, appAttest: appAttest
        )
        let response = try await http.postJSON(endpoint, request)
        guard response.isSuccess, response.json["success"] as? Bool == true else {
            throw PairingError.invalid(response.errorText ?? "Pairing failed (\(response.status))")
        }
        return try Self.parseRegistration(response.json, pairing: pairing, deviceName: deviceName, attested: appAttest != nil)
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
        if let token = pairing.pairingToken, !token.isBlank { body["pairingToken"] = token }
        if let pin = pairing.pinCode, !pin.isBlank { body["pinCode"] = pin }
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
