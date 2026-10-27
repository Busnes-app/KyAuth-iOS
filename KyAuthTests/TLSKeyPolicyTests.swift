import Foundation
import Security
import Testing
@testable import KyAuth

private struct TLSFixtureStats: Decodable {
    let bytes: UInt64
    let requests: UInt64
    let connections: UInt64
}

private struct TLSFixtureCase: Decodable {
    let name: String
    let port: Int
}

private struct TLSFixtureCertificate: Decodable {
    let certificate: String
}

/// Real TLS to the owned host fixture. No URLProtocol mock or trust override.
@Suite(.serialized)
struct TLSKeyPolicyTests {
    private let host = "kyauth-tls-test.invalid"

    /// Curves whose fixture peer this simulator's TLS stack does not negotiate,
    /// observed through the no-delegate control below: an ordinary URLSession
    /// is refused the same way, so the refusal is not the application's key
    /// policy, whose own decision on these keys is checked separately.
    private static let nativelyRefused: Set<String> = ["p521"]

    private func url(_ port: Int, _ path: String) -> URL {
        URL(string: "https://\(host):\(port)\(path)")!
    }

    private func stats(_ name: String) async throws -> TLSFixtureStats {
        let response = try await HTTPClient.shared.send("GET", url(46100, "/stats"), body: nil)
        try #require(response.status == 200)
        let values = try JSONDecoder().decode([String: TLSFixtureStats].self, from: response.body)
        return try #require(values[name])
    }

    private func certificate(_ name: String) async throws -> SecCertificate {
        let response = try await HTTPClient.shared.send("GET", url(46100, "/certificate/\(name)"), body: nil)
        try #require(response.status == 200)
        let fixture = try JSONDecoder().decode(TLSFixtureCertificate.self, from: response.body)
        let data = try #require(Data(base64Encoded: fixture.certificate))
        return try #require(SecCertificateCreateWithData(nil, data as CFData))
    }

    private func describeKey(_ certificate: SecCertificate) -> String {
        guard let key = SecCertificateCopyKey(certificate) else { return "key=unavailable" }
        let attributes = SecKeyCopyAttributes(key) as? [String: Any] ?? [:]
        let kind = attributes[kSecAttrKeyType as String] as? String ?? "unreported"
        let bits = attributes[kSecAttrKeySizeInBits as String] as? Int
        return "keyType=\(kind) bits=\(bits.map { String($0) } ?? "unreported") blockBytes=\(SecKeyGetBlockSize(key))"
    }

    @Test func nativeKeyAttributesDecideTheChainFloor() async throws {
        // Decided per certificate, so the floor is provable for a key type the
        // platform may never negotiate: a P-521 key satisfies it, and a key
        // this app cannot measure is refused rather than assumed strong.
        let expected: [(name: String, strong: Bool)] = [
            ("rsa2047", false), ("rsa2048", true), ("p256", true),
            ("p384", true), ("p521", true), ("ed25519", false),
        ]
        for item in expected {
            let leaf = try await certificate(item.name)
            print("KYAUTH_TLS_KEY case=\(item.name) strong=\(item.strong) \(describeKey(leaf))")
            #expect(TransportPolicy.hasStrongKey(leaf) == item.strong, "key floor: \(item.name)")
        }
        // Literal bits, never the rounded RSA block size, implement the minimum.
        let undersized = try await certificate("rsa2047")
        let key = try #require(SecCertificateCopyKey(undersized))
        let attributes = try #require(SecKeyCopyAttributes(key) as? [String: Any])
        #expect(attributes[kSecAttrKeyType as String] as? String == kSecAttrKeyTypeRSA as String)
        #expect(attributes[kSecAttrKeySizeInBits as String] as? Int == 2047)
        #expect(SecKeyGetBlockSize(key) == 256)
    }

    @Test func ordinaryNativeStrongCurveControls() async throws {
        // No delegate, trust override or application key policy: distinguish a
        // native TLS negotiation failure from the added all-chain key check.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let response = try await HTTPClient.shared.send("GET", url(46100, "/cases"), body: nil)
        let cases = try JSONDecoder().decode([TLSFixtureCase].self, from: response.body)
        for name in ["p256", "p384", "p521"] {
            let item = try #require(cases.first { $0.name == name })
            let before = try await stats(name)
            var accepted = false
            var refusal = "none"
            do {
                let (_, response) = try await session.data(from: url(item.port, "/native-curve-control"))
                accepted = (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                let native = error as NSError
                refusal = "\(native.domain) code=\(native.code)"
            }
            let after = try await stats(name)
            print("KYAUTH_TLS_ORDINARY case=\(name) accepted=\(accepted) refusal=\(refusal) applicationBytes=\(after.bytes - before.bytes)")
            #expect(after.connections > before.connections)
            if Self.nativelyRefused.contains(name) {
                // Recorded, not excused: a client with no key policy gets no
                // session either, so the platform refused it, and the peer must
                // still receive nothing.
                #expect(!accepted, "ordinary URLSession negotiated \(name); the application key policy would then be the only refusal")
                #expect(after.bytes == before.bytes)
                #expect(after.requests == before.requests)
            } else {
                #expect(accepted, "ordinary URLSession strong-curve control: \(name) \(refusal)")
                #expect(after.bytes > before.bytes)
                #expect(after.requests == before.requests + 1)
            }
        }
    }

    @Test func chainFloorsNativeTrustVersionsAndRedirectRefusal() async throws {
        print("KYAUTH_TLS_PLATFORM \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let response = try await HTTPClient.shared.send("GET", url(46100, "/cases"), body: nil)
        try #require(response.status == 200)
        let cases = try JSONDecoder().decode([TLSFixtureCase].self, from: response.body)
        let expected: Set<String> = [
            "rsa2048", "rsa2047", "p256", "rsa1024", "p384", "p521",
            "intermediate1024", "intermediate2047", "root1024", "root2047",
            "trusted1024", "trusted2047", "trusted2048", "wronghost", "expired", "untrusted",
            "tls10", "tls11", "tls12", "tls13",
        ]
        try #require(cases.count == expected.count && Set(cases.map(\.name)) == expected)
        let strong: Set<String> = ["rsa2048", "p256", "p384", "trusted2048", "tls12", "tls13"]
        for item in cases {
            let name = item.name
            let port = item.port
            let before = try await stats(name)
            let client = HTTPClient()
            var accepted = false
            do {
                let response = try await client.postJSON(url(port, "/probe"), ["public": "canary"])
                accepted = response.status == 200
            } catch {
                // Refusal must be accompanied by zero application bytes at the peer.
            }
            let after = try await stats(name)
            try #require(after.bytes >= before.bytes)
            let bytes = after.bytes - before.bytes
            let classification = strong.contains(name) ? "strong"
                : (Self.nativelyRefused.contains(name) ? "native-refusal" : "refused")
            print("KYAUTH_TLS_POLICY case=\(name) expected=\(classification) accepted=\(accepted) applicationBytes=\(bytes)")
            #expect(after.connections > before.connections)
            if strong.contains(name) {
                #expect(accepted)
                #expect(bytes > 0)
                #expect(after.requests == before.requests + 1)
            } else {
                // Weak keys, invalid trust, refused protocol versions and a peer
                // the platform will not negotiate all end the same way.
                #expect(!accepted)
                #expect(bytes == 0)
                #expect(after.requests == before.requests)
            }
            if name == "rsa2048", accepted {
                let repeated = try await client.postJSON(url(port, "/probe"), ["public": "repeat"])
                #expect(repeated.status == 200)
                let pooled = try await stats(name)
                #expect(pooled.requests == before.requests + 2)
                print("KYAUTH_TLS_REUSE requests=2 connections=\(pooled.connections - before.connections)")
            }
        }

        let before = try await stats("rsa2048")
        let redirected = try await HTTPClient().postJSON(url(46100, "/redirect"), ["public": "redirect canary"])
        #expect(redirected.status == 302)
        let after = try await stats("rsa2048")
        #expect(after.bytes == before.bytes)
        #expect(after.requests == before.requests)
    }
}
