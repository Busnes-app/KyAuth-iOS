import Foundation
import Security
import Testing
@testable import KyAuth

private struct TLSFixtureStats: Decodable {
    let bytes: UInt64
    let requests: UInt64
    let connections: UInt64
}

private struct TLSFixtureCertificate: Decodable {
    let certificate: String
}

/// Real TLS to the owned host fixture. No URLProtocol mock or trust override.
@Suite(.serialized)
struct TLSBaselineTests {
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

    @Test func unchangedClientTLSBaselineAndRedirectRefusal() async throws {
        print("KYAUTH_TLS_PLATFORM \(ProcessInfo.processInfo.operatingSystemVersionString)")
        for (name, port, strong) in [("rsa2048", 46101, true), ("rsa2047", 46102, false), ("p256", 46103, true)] {
            let before = try await stats(name)
            let client = HTTPClient()
            var accepted = false
            do {
                let response = try await client.postJSON(url(port, "/probe"), ["public": "canary"])
                accepted = response.status == 200
            } catch {
                // Baseline only: native rejection is recorded, not mistaken for a repair.
            }
            let after = try await stats(name)
            try #require(after.bytes >= before.bytes)
            let bytes = after.bytes - before.bytes
            print("KYAUTH_TLS_BASELINE case=\(name) accepted=\(accepted) applicationBytes=\(bytes)")
            if strong {
                #expect(accepted)
                #expect(bytes > 0)
            } else {
                // The result decides whether additional production enforcement is needed.
                #expect(accepted ? bytes > 0 : bytes == 0)
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
