import Foundation

/// Suite apps that may ask KyAuth for a KyIdentity ID token. Only apps of team TATYN4X57D can write
/// to the App Group, so the bundle ID in a request is trustworthy; this list says which of those apps
/// are consumers and where to return. See docs/specs/2026-10-11-ios-signon-handoff.md.
enum TrustedConsumers {
    struct Consumer: Equatable {
        let name: String
        let returnScheme: String
    }

    static let all: [String: Consumer] = [
        "org.kysecurity.mail": Consumer(name: "KyPost", returnScheme: "kypost"),
    ]
}

struct SignOnRequest: Equatable {
    let nonce: String
    let consumer: TrustedConsumers.Consumer
    let clientId: String
    let origin: String
    let issuer: String
}

enum SignOnResponse: Equatable {
    case ok(idToken: String)
    case cancelled
    case error(String)
}

enum SignOnRefusal: LocalizedError, Equatable {
    /// Nothing can be answered: no readable request for this nonce.
    case expired
    /// The request was read; its consumer gets this message.
    case refused(String, TrustedConsumers.Consumer)

    var errorDescription: String? {
        switch self {
        case .expired: "Sign-in request expired"
        case .refused(let message, _): message
        }
    }
}

/// The file exchange in the shared App Group. KyAuth reads and deletes `requests/`, and writes only
/// `responses/`; the consumer does the reverse.
struct SignOnHandoff {
    static let appGroup = "group.org.kysecurity.signon"
    static let maxAgeMs: Int64 = 120_000
    static let maxFutureSkewMs: Int64 = 30_000
    static let staleAfter: TimeInterval = 5 * 60

    let root: URL

    init?(root: URL? = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: SignOnHandoff.appGroup)?
        .appendingPathComponent("SignOn", isDirectory: true)) {
        guard let root else { return nil }
        self.root = root
    }

    static func isValidNonce(_ nonce: String) -> Bool {
        nonce.count == 43 && nonce.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_")
        }
    }

    /// Reads and deletes the request (single use), then validates it: age and consumer, client ID,
    /// origin, pairing, issuer, `canSignOn`.
    func take(nonce: String, paired: PairedAccount?, now: Date = Date()) throws -> SignOnRequest {
        guard Self.isValidNonce(nonce) else { throw SignOnRefusal.expired }
        let file = root.appendingPathComponent("requests/\(nonce).json")
        guard let data = try? Data(contentsOf: file) else { throw SignOnRefusal.expired }
        try? FileManager.default.removeItem(at: file)
        return try Self.validate(data, nonce: nonce, paired: paired, now: now)
    }

    static func validate(_ data: Data, nonce: String, paired: PairedAccount?, now: Date) throws -> SignOnRequest {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["v"] as? Int == 1, json["nonce"] as? String == nonce,
              let createdAt = (json["createdAtMs"] as? NSNumber)?.int64Value
        else { throw SignOnRefusal.expired }
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        guard createdAt <= nowMs + maxFutureSkewMs, nowMs - createdAt <= maxAgeMs else { throw SignOnRefusal.expired }

        guard let consumer = (json["consumer"] as? String).flatMap({ TrustedConsumers.all[$0] }) else {
            throw SignOnRefusal.expired
        }
        let clientId = json["clientId"] as? String
        guard DeviceAssertion.isValidClientId(clientId), let clientId else {
            throw SignOnRefusal.refused("The app sent an invalid sign-in request.", consumer)
        }
        let rawOrigin = json["origin"] as? String
        guard let origin = DeviceAssertion.relayOrigin(rawOrigin), origin == rawOrigin else {
            throw SignOnRefusal.refused("The server address must use HTTPS.", consumer)
        }
        guard let paired, let userId = paired.userId, !userId.isBlank else {
            throw SignOnRefusal.refused("KyAuth is not paired with KyIdentity.", consumer)
        }
        let issuer = json["issuer"] as? String ?? ""
        guard sameIssuer(issuer, paired.serverUrl) else {
            throw SignOnRefusal.refused("KyAuth is paired with a different KyIdentity server.", consumer)
        }
        guard paired.canSignOn else {
            throw SignOnRefusal.refused("Sign-in from this phone is turned off. Turn it on for this device on the KyIdentity devices page, then try again.", consumer)
        }
        return SignOnRequest(nonce: nonce, consumer: consumer, clientId: clientId, origin: origin, issuer: issuer)
    }

    /// scheme, host, port and path must match; two unparseable values are not the same issuer.
    static func sameIssuer(_ a: String, _ b: String) -> Bool {
        func canonical(_ value: String) -> String? {
            guard let url = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty
            else { return nil }
            let port = url.port ?? (scheme == "https" ? 443 : 80)
            return "\(scheme)://\(host):\(port)\(url.percentEncodedPath.trimmingTrailingSlashes())"
        }
        guard let x = canonical(a) else { return false }
        return x == canonical(b)
    }

    func write(_ response: SignOnResponse, nonce: String) throws {
        guard Self.isValidNonce(nonce) else { return }
        let directory = root.appendingPathComponent("responses", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encode(response, nonce: nonce).write(
            to: directory.appendingPathComponent("\(nonce).json"),
            options: [.atomic, .completeFileProtection]
        )
    }

    static func encode(_ response: SignOnResponse, nonce: String) -> Data {
        var json: [String: Any] = ["v": 1, "nonce": nonce]
        switch response {
        case .ok(let idToken):
            json["status"] = "ok"
            json["idToken"] = idToken
        case .cancelled:
            json["status"] = "cancelled"
        case .error(let message):
            json["status"] = "error"
            json["message"] = String(message.prefix(200))
        }
        return (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
    }

    static func returnURL(_ consumer: TrustedConsumers.Consumer, nonce: String) -> URL? {
        URL(string: "\(consumer.returnScheme)://kyidentity-signon?nonce=\(nonce)")
    }

    /// Deletes requests nobody answered. Responses belong to the consumer, which sweeps them.
    func sweepStaleRequests(now: Date = Date()) {
        let directory = root.appendingPathComponent("requests", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > Self.staleAfter {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
