import Foundation
import Security

/// One request to KyIdentity. Redirects are refused and nothing is cached or stored in cookies:
/// every endpoint KyAuth calls is pinned to the paired origin, and a redirect would leave it.
struct HTTPResponse: Sendable {
    let status: Int
    let body: Data

    var isSuccess: Bool { (200..<300).contains(status) }

    /// The body as a JSON object; empty or unreadable bodies are an empty object.
    var json: [String: Any] {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    }

    /// `error_description`, then `error`, from a refusal body.
    var errorText: String? {
        let json = json
        for key in ["error_description", "error"] {
            if let value = json[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }
}

enum HTTPError: LocalizedError {
    case unreachable

    var errorDescription: String? { "Could not reach KyIdentity. Check the connection and try again." }
}

final class HTTPClient: Sendable {
    static let shared = HTTPClient()

    private static let maxBodyBytes = 64 * 1024

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: TransportPolicy(), delegateQueue: nil)
    }

    func send(_ method: String, _ url: URL, body: Data?, contentType: String = "application/json") async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HTTPError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw HTTPError.unreachable }
        return HTTPResponse(status: http.statusCode, body: data.prefix(Self.maxBodyBytes))
    }

    func postJSON(_ url: URL, _ object: [String: Any]) async throws -> HTTPResponse {
        try await send("POST", url, body: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }
}

private final class TransportPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            return (.performDefaultHandling, nil)
        }
        // Preserve the platform's hostname, time, policy and anchor checks.
        guard let trust = challenge.protectionSpace.serverTrust,
              SecTrustEvaluateWithError(trust, nil),
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              !chain.isEmpty else { return (.cancelAuthenticationChallenge, nil) }

        for certificate in chain {
            guard let key = SecCertificateCopyKey(certificate),
                  let attributes = SecKeyCopyAttributes(key) as? [String: Any],
                  let kind = attributes[kSecAttrKeyType as String] as? String,
                  let bits = attributes[kSecAttrKeySizeInBits as String] as? Int else {
                return (.cancelAuthenticationChallenge, nil)
            }
            // RSA block size rounds 2047 bits to 256 bytes; use actual key bits.
            let strong = (kind == kSecAttrKeyTypeRSA as String && bits >= 2048)
                || (kind == kSecAttrKeyTypeECSECPrimeRandom as String && bits >= 256)
            guard strong else { return (.cancelAuthenticationChallenge, nil) }
        }
        return (.useCredential, URLCredential(trust: trust))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
