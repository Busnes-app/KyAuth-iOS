import Foundation

/// The short-lived pairing credential from a KyIdentity QR code or pairing link.
/// Held in memory only, never saved.
struct QrPairing: Equatable {
    let serverUrl: String
    var registrationUrl: String?
    var pairingToken: String?
    var pinCode: String?
    var userId: String?
    var username: String?
    var expiresAtEpochSeconds: Int64?

    init(
        serverUrl: String,
        registrationUrl: String? = nil,
        pairingToken: String? = nil,
        pinCode: String? = nil,
        userId: String? = nil,
        username: String? = nil,
        expiresAtEpochSeconds: Int64? = nil
    ) throws {
        guard !serverUrl.isBlank else { throw PairingError.invalid("Server URL is required") }
        guard !(pairingToken?.isBlank ?? true) || (!(pinCode?.isBlank ?? true) && !(userId?.isBlank ?? true)) else {
            throw PairingError.invalid("Pairing token or (PIN code and user ID) is required")
        }
        self.serverUrl = serverUrl
        self.registrationUrl = registrationUrl
        self.pairingToken = pairingToken
        self.pinCode = pinCode
        self.userId = userId
        self.username = username
        self.expiresAtEpochSeconds = expiresAtEpochSeconds
    }

    /// The credential the attestation challenge binds: the pairing token, else `userId|pinCode`.
    var credential: String {
        if let pairingToken, !pairingToken.isBlank { return pairingToken }
        return "\(userId ?? "")|\(pinCode ?? "")"
    }
}

/// Accepts KyIdentity's QR JSON and the `kyidentity://native-pair` link envelopes (plus the older
/// `kysignon` and `kypost` names). Either form must name an HTTPS origin before anything is sent.
enum QrPairingParser {
    private static let jsonTypes: Set<String> = ["kyidentity_device_pairing", "kysignon_device_pairing", "kypost_device_pairing"]
    private static let linkSchemes: Set<String> = ["kyidentity", "kysignon", "kypost"]

    static func parse(_ raw: String, now: Date = Date()) throws -> QrPairing {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw PairingError.invalid("QR code is empty") }
        let pairing = value.hasPrefix("{") ? try parseJson(value) : try parseLink(value)
        if let expires = pairing.expiresAtEpochSeconds, expires <= Int64(now.timeIntervalSince1970) {
            throw PairingError.invalid("Pairing credential has expired")
        }
        _ = try PairingEndpoint.validatedRegistrationUrl(pairing.serverUrl, pairing.registrationUrl)
        return pairing
    }

    private static func parseJson(_ value: String) throws -> QrPairing {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any] else {
            throw PairingError.invalid("QR code is not readable")
        }
        let type = json["type"] as? String ?? ""
        guard jsonTypes.contains(type) else { throw PairingError.invalid("Unsupported QR code type: \(type)") }
        func string(_ key: String) -> String? { (json[key] as? String)?.trimmedNonBlank }
        let expiresAt = (json["expiresAt"] as? NSNumber)?.int64Value
        return try QrPairing(
            serverUrl: string("serverUrl") ?? "",
            registrationUrl: string("registrationUrl"),
            pairingToken: string("pairingToken"),
            pinCode: string("pinCode"),
            userId: string("userId"),
            username: string("username"),
            expiresAtEpochSeconds: expiresAt
        )
    }

    private static func parseLink(_ value: String) throws -> QrPairing {
        guard let link = URLComponents(string: value),
              let scheme = link.scheme?.lowercased(), linkSchemes.contains(scheme),
              link.host?.lowercased() == "native-pair"
        else {
            throw PairingError.invalid("Unsupported pairing link")
        }
        var params: [String: String] = [:]
        for item in link.queryItems ?? [] where params[item.name] == nil {
            params[item.name] = item.value
        }
        func param(_ keys: String...) -> String? { keys.lazy.compactMap { params[$0]?.trimmedNonBlank }.first }
        return try QrPairing(
            serverUrl: param("srv") ?? "",
            registrationUrl: param("reg"),
            pairingToken: param("pt"),
            pinCode: param("pin"),
            userId: param("sub", "uid"),
            username: param("user", "username"),
            expiresAtEpochSeconds: param("exp").flatMap { Int64($0) }
        )
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var trimmedNonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
