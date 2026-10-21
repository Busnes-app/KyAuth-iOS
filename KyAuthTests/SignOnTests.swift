import CryptoKit
import Foundation
import Testing
@testable import KyAuth

@MainActor
struct DeviceAssertionTests {
    private func decode(_ segment: String) -> [String: Any] {
        var base64 = segment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return (try? JSONSerialization.jsonObject(with: Data(base64Encoded: base64)!)) as? [String: Any] ?? [:]
    }

    @Test func signingInputHasPinnedHeaderAndClaims() {
        let input = DeviceAssertion.signingInput(
            deviceId: "dev-1", userId: "user-1", serverUrl: "https://id.example.com/",
            clientId: "kypost", origin: "https://mail.example.com", now: 1000, jti: "j-1"
        )
        let parts = input.split(separator: ".").map(String.init)
        let header = decode(parts[0])
        #expect(header.count == 3)
        #expect(header["alg"] as? String == "ES256")
        #expect(header["typ"] as? String == "JWT")
        #expect(header["kid"] as? String == "dev-1")
        let claims = decode(parts[1])
        #expect(claims.count == 8)
        #expect(claims["iss"] as? String == "device:dev-1")
        #expect(claims["sub"] as? String == "user-1")
        #expect(claims["aud"] as? String == "https://id.example.com/oauth/token")
        #expect(claims["client_id"] as? String == "kypost")
        #expect(claims["iat"] as? Int == 1000)
        #expect(claims["exp"] as? Int == 1120)
        #expect(claims["jti"] as? String == "j-1")
        #expect(claims["origin"] as? String == "https://mail.example.com")
    }

    @Test func relayOriginNormalisesHttpsAndRefusesEverythingElse() {
        let cases: [(String, String?)] = [
            ("https://mail.example.com/", "https://mail.example.com"),
            ("https://mail.example.com/relay/v1?x=1#f", "https://mail.example.com"),
            ("https://Mail.EXAMPLE.com", "https://mail.example.com"),
            ("HTTPS://mail.example.com", "https://mail.example.com"),
            ("https://mail.example.com:443/", "https://mail.example.com"),
            ("https://mail.example.com:8443/relay", "https://mail.example.com:8443"),
            ("http://mail.example.com", nil),
            ("https://user:pw@mail.example.com", nil),
            ("https://user@mail.example.com", nil),
            ("", nil),
            ("   ", nil),
            ("mail.example.com", nil),
            ("https:///path", nil),
            ("https:mail.example.com", nil),
            ("https://mail.example.com:0/", nil),
            ("https://mail.example.com:65536/", nil),
            ("https://mail.example.com:65535/", "https://mail.example.com:65535"),
            ("https://" + String(repeating: "a", count: 250) + ".com", nil),
        ]
        for (raw, want) in cases {
            #expect(DeviceAssertion.relayOrigin(raw) == want, "relayOrigin(\(raw))")
        }
        #expect(DeviceAssertion.relayOrigin(nil) == nil)
    }

    @Test func compactSignatureVerifiesAsRawES256() throws {
        let key = P256.Signing.PrivateKey()
        let input = DeviceAssertion.signingInput(
            deviceId: "d", userId: "u", serverUrl: "https://id.example.com", clientId: "c",
            origin: "https://m.example.com", now: 1, jti: "j"
        )
        let signature = try key.signature(for: Data(input.utf8))
        let compact = DeviceAssertion.compact(input, rawSignature: signature.rawRepresentation)
        let last = String(compact.split(separator: ".")[2])
        #expect(!last.contains("=") && !last.contains("+") && !last.contains("/"))
        var base64 = last.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        let raw = try #require(Data(base64Encoded: base64))
        #expect(raw.count == 64)
        #expect(key.publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: raw), for: Data(input.utf8)))
    }

    @Test func clientIds() {
        #expect(DeviceAssertion.isValidClientId("kypost"))
        #expect(DeviceAssertion.isValidClientId("a.b_c:d-e"))
        #expect(!DeviceAssertion.isValidClientId(""))
        #expect(!DeviceAssertion.isValidClientId("a b"))
        #expect(!DeviceAssertion.isValidClientId(String(repeating: "a", count: 129)))
        #expect(!DeviceAssertion.isValidClientId(nil))
    }
}

@MainActor
struct TokenClientTests {
    @Test func formBodyIsJwtBearerGrant() {
        #expect(TokenClient.formBody(clientId: "kypost", assertion: "h.c.s") ==
            "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=h.c.s&client_id=kypost")
    }

    @Test func parse() {
        #expect(TokenClient.parse(status: 200, json: ["id_token": "eyJ.x.y"]) == .success(idToken: "eyJ.x.y"))
        #expect(TokenResult.success(idToken: "secret").description == "success(redacted)")
        #expect(TokenClient.parse(status: 200, json: ["access_token": "a"]) == .failure("KyIdentity returned no identity token."))
        #expect(TokenClient.parse(status: 400, json: ["error_description": "signon_not_permitted"])
            == .failure("This account cannot sign in to apps from this device right now. Use web sign-in."))
        #expect(TokenClient.parse(status: 400, json: ["error_description": "something_new"]) == .failure("KyIdentity refused the sign-in (400)."))
        if case .failure(let message) = TokenClient.parse(status: 400, json: ["error_description": "device_signon_disabled"]) {
            #expect(message.contains("KyIdentity devices page"))
        } else {
            Issue.record("expected failure")
        }
        if case .failure(let message) = TokenClient.parse(status: 429, json: [:]) {
            #expect(message.contains("Try again"))
        } else {
            Issue.record("expected failure")
        }
    }
}

@MainActor
struct SignOnHandoffTests {
    let nonce = String(repeating: "A", count: 42) + "_"
    let paired = PairedAccount(
        serverUrl: "https://id.example.com", deviceId: "d", deviceName: "iPhone", userId: "u", canSignOn: true
    )
    let now = Date(timeIntervalSince1970: 1_000_000)

    func request(_ overrides: [String: Any] = [:]) -> Data {
        var json: [String: Any] = [
            "v": 1, "nonce": nonce, "consumer": "org.kysecurity.mail", "clientId": "kypost",
            "origin": "https://relay.example.com", "issuer": "https://ID.example.com:443/",
            "createdAtMs": 1_000_000_000 - 5_000,
        ]
        json.merge(overrides) { $1 }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func acceptsAWellFormedRequest() throws {
        let accepted = try SignOnHandoff.validate(request(), nonce: nonce, paired: paired, now: now)
        #expect(accepted.consumer.name == "KyPost")
        #expect(accepted.origin == "https://relay.example.com")
        #expect(SignOnHandoff.returnURL(accepted.consumer, nonce: nonce)?.absoluteString == "kypost://kyidentity-signon?nonce=\(nonce)")
    }

    @Test func expiredOrUnknownRequestsHaveNoAnswer() {
        for bad in [
            request(["createdAtMs": 1_000_000_000 - 120_001]),
            request(["createdAtMs": 1_000_000_000 + 30_001]),
            request(["consumer": "com.example.other"]),
            request(["nonce": "other"]),
            request(["v": 2]),
            Data("not json".utf8),
        ] {
            #expect(throws: SignOnRefusal.expired) { try SignOnHandoff.validate(bad, nonce: nonce, paired: paired, now: now) }
        }
    }

    @Test func refusalsGoBackToTheConsumer() {
        let kypost = TrustedConsumers.all["org.kysecurity.mail"]!
        func refusal(_ data: Data, paired: PairedAccount?) -> String? {
            do {
                _ = try SignOnHandoff.validate(data, nonce: nonce, paired: paired, now: now)
                return nil
            } catch SignOnRefusal.refused(let message, let consumer) {
                #expect(consumer == kypost)
                return message
            } catch {
                return "unexpected \(error)"
            }
        }
        #expect(refusal(request(["clientId": "a b"]), paired: paired) == "The app sent an invalid sign-in request.")
        #expect(refusal(request(["origin": "https://relay.example.com/"]), paired: paired) == "The server address must use HTTPS.")
        #expect(refusal(request(["origin": "http://relay.example.com"]), paired: paired) == "The server address must use HTTPS.")
        #expect(refusal(request(), paired: nil) == "KyAuth is not paired with KyIdentity.")
        #expect(refusal(request(["issuer": "https://other.example.com"]), paired: paired) == "KyAuth is paired with a different KyIdentity server.")
        #expect(refusal(request(["issuer": "https://id.example.com/sub"]), paired: paired) == "KyAuth is paired with a different KyIdentity server.")
        var off = paired
        off.canSignOn = false
        #expect(refusal(request(), paired: off)?.contains("turned off") == true)
    }

    @Test func takeIsSingleUseAndResponsesAreWritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let handoff = try #require(SignOnHandoff(root: root))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("requests"), withIntermediateDirectories: true)
        let fresh = request(["createdAtMs": Int64(Date().timeIntervalSince1970 * 1000)])
        try fresh.write(to: root.appendingPathComponent("requests/\(nonce).json"))
        _ = try handoff.take(nonce: nonce, paired: paired)
        #expect(throws: SignOnRefusal.expired) { try handoff.take(nonce: nonce, paired: paired) }
        #expect(throws: SignOnRefusal.expired) { try handoff.take(nonce: "../../etc", paired: paired) }

        try handoff.write(.ok(idToken: "tok"), nonce: nonce)
        let written = try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("responses/\(nonce).json"))
        ) as? [String: Any]
        #expect(written?["status"] as? String == "ok")
        #expect(written?["idToken"] as? String == "tok")
        #expect(written?["nonce"] as? String == nonce)
        try? FileManager.default.removeItem(at: root)
    }

    @Test func responseEncoding() throws {
        func decode(_ response: SignOnResponse) -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: SignOnHandoff.encode(response, nonce: "n"))) as? [String: Any] ?? [:]
        }
        #expect(decode(.cancelled)["status"] as? String == "cancelled")
        #expect(decode(.cancelled)["idToken"] == nil)
        let error = decode(.error(String(repeating: "x", count: 300)))
        #expect(error["status"] as? String == "error")
        #expect((error["message"] as? String)?.count == 200)
        #expect(decode(.ok(idToken: "t"))["v"] as? Int == 1)
    }

    @Test func nonceFormat() {
        #expect(SignOnHandoff.isValidNonce(nonce))
        #expect(!SignOnHandoff.isValidNonce(String(repeating: "A", count: 44)))
        #expect(!SignOnHandoff.isValidNonce(String(repeating: "A", count: 42) + "/"))
    }
}

@MainActor
struct SignOnBusyTests {
    let paired = PairedAccount(
        serverUrl: "https://id.example.com", deviceId: "d", deviceName: "iPhone", userId: "u", canSignOn: true
    )

    private func nonce(_ c: Character) -> String { String(repeating: c, count: 43) }

    private func writeRequest(_ nonce: String, root: URL) throws {
        let json: [String: Any] = [
            "v": 1, "nonce": nonce, "consumer": "org.kysecurity.mail", "clientId": "kypost",
            "origin": "https://relay.example.com", "issuer": "https://id.example.com",
            "createdAtMs": Int64(Date().timeIntervalSince1970 * 1000),
        ]
        try FileManager.default.createDirectory(at: root.appendingPathComponent("requests"), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json).write(to: root.appendingPathComponent("requests/\(nonce).json"))
    }

    @Test func aFailedBusyAnswerIsKeptForRetryAndTheActiveSignInStays() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(account: paired, makeHandoff: { SignOnHandoff(root: root) })
        let a = nonce("A"), b = nonce("B")
        try writeRequest(a, root: root)
        try writeRequest(b, root: root)

        model.handleOpenURL(URL(string: "kyauth://signon?nonce=\(a)")!)
        #expect(model.signOnRequest?.nonce == a)

        // A file where the responses directory belongs makes every response write fail.
        try Data().write(to: root.appendingPathComponent("responses"))
        model.handleOpenURL(URL(string: "kyauth://signon?nonce=\(b)")!)
        #expect(model.signOnRequest?.nonce == a)
        #expect(model.unsentResponseNonces == [b])

        try FileManager.default.removeItem(at: root.appendingPathComponent("responses"))
        model.retryUnsentResponses()
        #expect(model.unsentResponseNonces.isEmpty)
        let written = try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("responses/\(b).json"))
        ) as? [String: Any]
        #expect(written?["status"] as? String == "error")
        #expect(model.signOnRequest?.nonce == a)

        model.retryUnsentResponses(now: Date().addingTimeInterval(1000))
        try? FileManager.default.removeItem(at: root)
    }

    @Test func unsentAnswersExpireWithTheConsumersWait() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(account: paired, makeHandoff: { SignOnHandoff(root: root) })
        let a = nonce("C"), b = nonce("D")
        try writeRequest(a, root: root)
        try writeRequest(b, root: root)
        model.handleOpenURL(URL(string: "kyauth://signon?nonce=\(a)")!)
        try Data().write(to: root.appendingPathComponent("responses"))
        model.handleOpenURL(URL(string: "kyauth://signon?nonce=\(b)")!)
        #expect(model.unsentResponseNonces == [b])
        model.retryUnsentResponses(now: Date().addingTimeInterval(181))
        #expect(model.unsentResponseNonces.isEmpty)
        try? FileManager.default.removeItem(at: root)
    }
}
