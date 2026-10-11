import Foundation

enum PairingError: LocalizedError, Equatable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

/// Validates the KyIdentity server a pairing names, and builds every endpoint KyAuth calls from it.
/// Release builds require HTTPS; debug builds also accept loopback HTTP.
enum PairingEndpoint {
    static func validateServerUrl(_ serverUrl: String) throws -> String {
        let trimmed = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let server = URLComponents(string: trimmed),
              let host = server.host, !host.isEmpty,
              server.user == nil, server.password == nil, server.query == nil, server.fragment == nil
        else {
            throw PairingError.invalid("Enter a complete server URL without credentials or a path query")
        }
        guard isAllowedScheme(server.scheme, host: host) else {
            throw PairingError.invalid("Server must use HTTPS except for loopback development")
        }
        return trimmed.trimmingTrailingSlashes()
    }

    static func registrationUrl(_ serverUrl: String) throws -> URL {
        try endpoint(serverUrl, "/api/notifications/native/register")
    }

    static func tokenUrl(_ serverUrl: String) throws -> URL {
        try endpoint(serverUrl, "/oauth/token")
    }

    static func mfaRespondUrl(_ serverUrl: String) throws -> URL {
        try endpoint(serverUrl, "/api/mfa/push/respond")
    }

    static func pushTokenUrl(_ serverUrl: String, deviceId: String) throws -> URL {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        guard let encoded = deviceId.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw PairingError.invalid("Invalid device ID")
        }
        return try endpoint(serverUrl, "/api/notifications/native/devices/\(encoded)/push-token")
    }

    /// The registration URL a QR code names, which must share the server's origin; else the default.
    static func validatedRegistrationUrl(_ serverUrl: String, _ candidate: String?) throws -> URL {
        let fallback = try registrationUrl(serverUrl)
        guard let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty else {
            return fallback
        }
        guard let registration = URLComponents(string: candidate),
              let host = registration.host, !host.isEmpty
        else {
            throw PairingError.invalid("Invalid registration URL")
        }
        guard isAllowedScheme(registration.scheme, host: host) else {
            throw PairingError.invalid("Registration URL must use HTTPS")
        }
        guard registration.user == nil, registration.password == nil,
              registration.query == nil, registration.fragment == nil
        else {
            throw PairingError.invalid("Invalid registration URL")
        }
        guard let server = URLComponents(string: serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)),
              sameOrigin(registration, server), let url = registration.url
        else {
            throw PairingError.invalid("Registration URL must be on the same server as the QR code")
        }
        return url
    }

    private static func endpoint(_ serverUrl: String, _ path: String) throws -> URL {
        guard var server = URLComponents(string: try validateServerUrl(serverUrl)) else {
            throw PairingError.invalid("Invalid server URL")
        }
        server.percentEncodedPath = server.percentEncodedPath.trimmingTrailingSlashes() + path
        guard let url = server.url else { throw PairingError.invalid("Invalid server URL") }
        return url
    }

    private static func isAllowedScheme(_ scheme: String?, host: String) -> Bool {
        if scheme == "https" { return true }
        #if DEBUG
        return scheme == "http" && isLoopback(host)
        #else
        return false
        #endif
    }

    private static func sameOrigin(_ a: URLComponents, _ b: URLComponents) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased()
            && a.host?.lowercased() == b.host?.lowercased()
            && effectivePort(a) == effectivePort(b)
    }

    private static func effectivePort(_ url: URLComponents) -> Int {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }

    private static func isLoopback(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
    }
}

extension String {
    func trimmingTrailingSlashes() -> String {
        var value = self
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }
}
