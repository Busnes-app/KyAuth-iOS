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

    private func url(_ port: Int, _ path: String) -> URL {
        URL(string: "https://\(host):\(port)\(path)")!
    }

    private func stats(_ name: String) async throws -> TLSFixtureStats {
        let response = try await HTTPClient.shared.send("GET", url(46100, "/stats"), body: nil)
        try #require(response.status == 200)
        let values = try JSONDecoder().decode([String: TLSFixtureStats].self, from: response.body)
        return try #require(values[name])
    }

    @Test func nativeRSAAttributesUseActualModulusBits() async throws {
        let response = try await HTTPClient.shared.send("GET", url(46100, "/certificate/rsa2047"), body: nil)
        try #require(response.status == 200)
        let fixture = try JSONDecoder().decode(TLSFixtureCertificate.self, from: response.body)
        let data = try #require(Data(base64Encoded: fixture.certificate))
        let certificate = try #require(SecCertificateCreateWithData(nil, data as CFData))
        let key = try #require(SecCertificateCopyKey(certificate))
        let attributes = try #require(SecKeyCopyAttributes(key) as? [String: Any])
        #expect(attributes[kSecAttrKeyType as String] as? String == kSecAttrKeyTypeRSA as String)
        #expect(attributes[kSecAttrKeySizeInBits as String] as? Int == 2047)
        print("KYAUTH_TLS_ATTRIBUTES actualRSA=2047 blockBytes=\(SecKeyGetBlockSize(key))")
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
            do {
                let (_, response) = try await session.data(from: url(item.port, "/native-curve-control"))
                #expect((response as? HTTPURLResponse)?.statusCode == 200,
                        "Ordinary URLSession strong-curve control: \(name)")
            } catch {
                let native = error as NSError
                Issue.record("Ordinary URLSession refused \(name): \(native.domain) code=\(native.code)")
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
        let strong: Set<String> = ["rsa2048", "p256", "p384", "p521", "trusted2048", "tls12", "tls13"]
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
            print("KYAUTH_TLS_POLICY case=\(name) accepted=\(accepted) applicationBytes=\(bytes)")
            #expect(after.connections > before.connections)
            if strong.contains(name) {
                #expect(accepted)
                #expect(bytes > 0)
                #expect(after.requests == before.requests + 1)
            } else {
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
