import CryptoKit
import Foundation
import Testing
@testable import KyAuth

@MainActor
struct PairingFormTests {
    private func draft() -> PairingDraft {
        PairingDraft(serverUrl: "https://id.example.com", userId: "u-1", pinCode: "123456", deviceName: "Test")
    }

    /// Pairing by link or by hand means leaving KyAuth, which locks it; the form must survive that.
    @Test func aLockKeepsTheFormAndShowsItAgain() {
        let model = AppModel(account: nil, pushState: PushState())
        model.startDemo() // the one way to an unlocked model without Face ID
        model.pairingDraft = draft()
        model.lock()
        #expect(model.resumePairing)
        #expect(model.pairingDraft == draft())

        // The form's views going away with the lock is not the user closing it.
        model.pairingFormClosed()
        #expect(model.resumePairing)
        #expect(model.pairingDraft == draft())
    }

    @Test func closingTheFormWhileUnlockedForgetsIt() {
        let model = AppModel(account: nil, pushState: PushState())
        model.startDemo()
        model.pairingDraft = draft()
        model.pairingFormClosed()
        #expect(model.pairingDraft == nil)
        #expect(!model.resumePairing)
    }

    @Test func noFormWasOpenSoNothingComesBack() {
        let model = AppModel(account: nil, pushState: PushState())
        model.startDemo()
        model.lock()
        #expect(!model.resumePairing)
    }

    @Test func aKnownPushTokenIsUsedAtOnce() async throws {
        let model = AppModel(account: nil, pushState: PushState(latestToken: "ab"))
        #expect(try await model.pushTokenForPairing(timeout: .zero) == "ab")
    }

    @Test func pairingStopsWaitingForApplePush() async {
        let model = AppModel(account: nil, pushState: PushState())
        await #expect(throws: PairingError.invalid("Apple Push did not answer. Check the connection, then try again.")) {
            try await model.pushTokenForPairing(timeout: .milliseconds(300))
        }
    }

    @Test func anApplePushRefusalEndsTheWaitWithItsReason() async {
        let model = AppModel(account: nil, pushState: PushState())
        let refusal = URLError(.notConnectedToInternet)
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            model.didFailToRegisterForPush(refusal)
        }
        let start = ContinuousClock.now
        await #expect(throws: PairingError.invalid("Apple Push is unavailable: \(refusal.localizedDescription)")) {
            try await model.pushTokenForPairing(timeout: .seconds(10))
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    /// A second pairing would replace the first one's device key, and its failure would delete it.
    @Test func onePairingAtATimeAndItsErrorOutlivesTheForm() async throws {
        let model = AppModel(account: nil, pushState: PushState())
        model.pairingDraft = draft()
        let pairing = try QrPairing(serverUrl: "https://id.example.com", pinCode: "123456", userId: "u-1")
        let first = Task { try await model.pair(pairing, deviceName: "Test") }
        while !model.isPairing { await Task.yield() }
        await #expect(throws: PairingError.invalid("KyAuth is already pairing. Wait for it to finish.")) {
            try await model.pair(pairing, deviceName: "Test")
        }
        first.cancel()
        _ = await first.result
        #expect(!model.isPairing)
        #expect(model.pairingDraft?.error != nil)
    }

    /// A scanned code that expired while it waited for a tap leaves the working pairing alone.
    @Test func anExpiredCodeKeepsTheCurrentPairing() async throws {
        let account = PairedAccount(
            serverUrl: "https://id.example.com", deviceId: "d", deviceName: "iPhone", userId: "u", canSignOn: true
        )
        let model = AppModel(account: account, pushState: PushState(latestToken: "ab"))
        let pairing = try QrPairing(
            serverUrl: "https://id.example.com", pairingToken: "pt-1", userId: "u-1",
            expiresAtEpochSeconds: Int64(Date().timeIntervalSince1970) - 1
        )
        await #expect(throws: PairingError.invalid("Pairing credential has expired")) {
            try await model.pair(pairing, deviceName: "Test")
        }
        #expect(model.account == account)
    }
}

@MainActor
struct QrPairingParserTests {
    let future = Int64(Date().timeIntervalSince1970) + 90

    @Test func parsesKyIdentityJson() throws {
        let pairing = try QrPairingParser.parse("""
        {"type":"kyidentity_device_pairing","serverUrl":"https://id.example.com","pairingToken":"pt-1",
         "userId":"u-1","username":"ada","expiresAt":\(future)}
        """)
        #expect(pairing.serverUrl == "https://id.example.com")
        #expect(pairing.pairingToken == "pt-1")
        #expect(pairing.username == "ada")
        #expect(pairing.credential.hasPrefix("pair1:"))
    }

    @Test func parsesDeepLinkWithPin() throws {
        let pairing = try QrPairingParser.parse(
            "kyidentity://native-pair?srv=https%3A%2F%2Fid.example.com&pin=123456&sub=u-9&user=ada&exp=\(future)"
        )
        #expect(pairing.pinCode == "123456")
        #expect(pairing.userId == "u-9")
        #expect(pairing.credential == "u-9|123456")
    }

    @Test func refusesUnknownTypeExpiredAndHttp() {
        #expect(throws: PairingError.self) {
            try QrPairingParser.parse(#"{"type":"other","serverUrl":"https://id.example.com","pairingToken":"t","userId":"u"}"#)
        }
        #expect(throws: PairingError.self) {
            try QrPairingParser.parse(#"{"type":"kyidentity_device_pairing","serverUrl":"https://id.example.com","pairingToken":"t","userId":"u","expiresAt":1}"#)
        }
        #expect(throws: PairingError.self) {
            try QrPairingParser.parse(#"{"type":"kyidentity_device_pairing","serverUrl":"http://id.example.com","pairingToken":"t","userId":"u"}"#)
        }
        // Pairing proof v1 sends the user ID instead of the token.
        #expect(throws: PairingError.self) {
            try QrPairingParser.parse(#"{"type":"kyidentity_device_pairing","serverUrl":"https://id.example.com","pairingToken":"t"}"#)
        }
        #expect(throws: PairingError.self) {
            try QrPairingParser.parse("kyidentity://native-pair?srv=https%3A%2F%2Fid.example.com&pin=1")
        }
        #expect(throws: PairingError.self) { try QrPairingParser.parse("https://example.com") }
    }

    @Test func registrationUrlMustShareOrigin() throws {
        #expect(throws: PairingError.self) {
            try QrPairingParser.parse(#"{"type":"kyidentity_device_pairing","serverUrl":"https://id.example.com","registrationUrl":"https://evil.example.com/api/notifications/native/register","pairingToken":"t","userId":"u"}"#)
        }
        let ok = try PairingEndpoint.validatedRegistrationUrl(
            "https://id.example.com", "https://ID.example.com:443/api/notifications/native/register"
        )
        #expect(ok.host() == "ID.example.com")
    }
}

/// The Codes tab scanner: setup codes add an account, pairing codes go to pairing.
struct ScannedCodeTests {
    @Test func setupCodeAddsAnAccount() throws {
        guard case .account(let entry) = try ScannedCode.parse("otpauth://totp/Mail:me?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=Mail")
        else { Issue.record("expected an account"); return }
        #expect(entry.issuer == "Mail")
    }

    @Test func pairingCodesGoToPairing() throws {
        for raw in [
            #"{"type":"kyidentity_device_pairing","serverUrl":"https://id.example.com","pairingToken":"t","userId":"u"}"#,
            "kyidentity://native-pair?srv=https%3A%2F%2Fid.example.com&pt=t&sub=u",
        ] {
            guard case .pairing(let pairing) = try ScannedCode.parse(raw) else { Issue.record("expected pairing: \(raw)"); continue }
            #expect(pairing.serverUrl == "https://id.example.com")
        }
    }

    @Test func badPairingCodeSaysWhyAndOtherCodesAreRefused() {
        let expired = #"{"type":"kyidentity_device_pairing","serverUrl":"https://id.example.com","pairingToken":"t","userId":"u","expiresAt":1}"#
        #expect(throws: PairingError.self) { try ScannedCode.parse(expired) }
        #expect(throws: TotpError.self) { try ScannedCode.parse("https://example.com") }
        #expect(throws: TotpError.self) { try ScannedCode.parse("otpauth://hotp/x?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP") }
    }
}

@MainActor
struct PairingEndpointTests {
    @Test func buildsEndpointsUnderTheServerPath() throws {
        #expect(try PairingEndpoint.registrationUrl("https://id.example.com/").absoluteString
            == "https://id.example.com/api/notifications/native/register")
        #expect(try PairingEndpoint.tokenUrl("https://id.example.com/kyidentity").absoluteString
            == "https://id.example.com/kyidentity/oauth/token")
        #expect(try PairingEndpoint.pushTokenUrl("https://id.example.com", deviceId: "d 1/x").absoluteString
            == "https://id.example.com/api/notifications/native/devices/d%201%2Fx/push-token")
    }

    @Test func refusesCredentialsQueriesAndPlainHttp() {
        #expect(throws: PairingError.self) { try PairingEndpoint.validateServerUrl("https://u:p@id.example.com") }
        #expect(throws: PairingError.self) { try PairingEndpoint.validateServerUrl("https://id.example.com?x=1") }
        #expect(throws: PairingError.self) { try PairingEndpoint.validateServerUrl("http://id.example.com") }
        #expect(throws: PairingError.self) { try PairingEndpoint.validateServerUrl("id.example.com") }
    }

    #if DEBUG
    @Test func debugAllowsLoopbackHttp() throws {
        #expect(try PairingEndpoint.validateServerUrl("http://127.0.0.1:8080") == "http://127.0.0.1:8080")
    }
    #endif
}

@MainActor
struct PairingClientTests {
    let pairing = try! QrPairing(serverUrl: "https://id.example.com/", pairingToken: "pt", userId: "u-1", username: "ada")

    @Test func requestAlwaysNamesIosAndCarriesAppAttestAndPushKeys() throws {
        let keys = try PushKeys(stored: PushVectors.receiverStored)
        let body = PairingClient.requestBody(
            pairing: pairing, deviceName: " Ada's iPhone ", deviceIdentifier: "inst-1", pushToken: "abcd",
            pushKeys: keys, publicKey: "PK", appAttest: AppAttestation(keyId: "kid", attestation: "obj")
        )
        #expect(body["platform"] as? String == "ios")
        #expect(body["deviceName"] as? String == "Ada's iPhone")
        #expect(body["pushToken"] as? String == "abcd")
        #expect(body["pairingToken"] == nil)
        #expect(body["pinCode"] == nil)
        #expect(body["userId"] as? String == "u-1")
        #expect(body["pushTransport"] == nil)
        #expect(body["pushP256dh"] as? String == PushVectors.receiverP256dh)
        #expect(body["pushAuth"] as? String == PushVectors.auth)
        #expect((body["appAttest"] as? [String: String]) == ["keyId": "kid", "attestation": "obj"])
        let plain = PairingClient.requestBody(
            pairing: pairing, deviceName: "x", deviceIdentifier: "i", pushToken: "t", pushKeys: keys, publicKey: "PK", appAttest: nil
        )
        #expect(plain["appAttest"] == nil)
    }

    @Test func parsesRegistrationAndClassifiesAttestation() throws {
        let attested = try PairingClient.parseRegistration(
            ["success": true, "deviceId": "d-1", "device": ["userId": "u-2", "canSignOn": true, "attestedLevel": "appattest"]],
            pairing: pairing, deviceName: "iPhone", attested: true
        )
        #expect(attested.serverUrl == "https://id.example.com")
        #expect(attested.userId == "u-2")
        #expect(attested.canSignOn)
        #expect(attested.attestedLevel == "appattest")
        #expect(attested.attestationReason == "")

        let silent = try PairingClient.parseRegistration(
            ["success": true, "deviceId": "d-1", "device": [String: Any]()], pairing: pairing, deviceName: "iPhone", attested: true
        )
        #expect(silent.attestationReason == AttestationReason.serverUnsupported)
        #expect(silent.userId == "u-1")

        let unavailable = try PairingClient.parseRegistration(
            ["deviceId": "d", "device": ["attestedLevel": "none"]], pairing: pairing, deviceName: "i", attested: false
        )
        #expect(unavailable.attestationReason == AttestationReason.appAttestUnavailable)

        let refused = try PairingClient.parseRegistration(
            ["deviceId": "d", "device": ["attestedLevel": "strongbox"]], pairing: pairing, deviceName: "i", attested: true
        )
        #expect(refused.attestedLevel == "none")
        #expect(refused.attestationReason == AttestationReason.notAccepted)

        #expect(throws: PairingError.self) {
            try PairingClient.parseRegistration(["success": true], pairing: pairing, deviceName: "i", attested: false)
        }
    }

    @Test func appAttestClientDataBindsCredentialAndKey() {
        #expect(String(decoding: AppAttestor.clientData(credential: "pt", publicKey: "PK=="), as: UTF8.self)
            == "kyidentity-appattest-v1|pt|PK==")
    }
}

/// Pairing proof v1. Golden vector shared with KyIdentity-server and KyAuth Android.
@MainActor
struct PairingProofTests {
    let pairing = try! QrPairing(
        serverUrl: "https://id.example.com", pairingToken: "00112233445566778899aabbccddeeff0011223344556677", userId: "user-1"
    )
    let request = Data(#"{"userId":"user-1","deviceName":"Pixel","deviceIdentifier":"inst-1","platform":"android","publicKey":"BAAA","pushToken":"tok","pushTransport":"fcm"}"#.utf8)
    let response = Data((#"{"success":true,"deviceId":"dev-1","device":{"id":"dev-1"}}"# + "\n").utf8)
    let reply = "QsV0h3Srdjg805wx19o-D3Ee1KhzmKAz1RqP4Zu0Q-Y"
    let cred = "pair1:8f7bb6e4f056bb6d1846aa7544964867c93afdd56ec29c73c46aac8ebd8f8d76"

    private func answer(_ proof: String?, body: Data? = nil, status: Int = 201) -> HTTPResponse {
        HTTPResponse(status: status, body: body ?? response, headers: proof.map { ["kyidentity-pairing-proof": $0] } ?? [:])
    }

    @Test func matchesGoldenVector() throws {
        let proof = try #require(try PairingProof(pairing))
        #expect(proof.request(request) == "mJoloQsGw4y-mlo2Lo3pMsesJrVna3FPQN4DuV5HaTs")
        #expect(PairingProof.requestHash(request) == "cykwj-49G__TJq22JeLvRDBE4qzm3_BRgfznUMMoiag")
        #expect(proof.acceptsReply(reply, request: request, response: response))
        #expect(pairing.credential == cred)
        #expect(String(decoding: AppAttestor.clientData(credential: pairing.credential, publicKey: "BAAA"), as: UTF8.self)
            == "kyidentity-appattest-v1|\(cred)|BAAA")
    }

    @Test func originIsCanonical() throws {
        let spelled = try QrPairing(
            serverUrl: "https://ID.Example.com:443/", pairingToken: "00112233445566778899aabbccddeeff0011223344556677", userId: "user-1"
        )
        #expect(try #require(try PairingProof(spelled)).request(request) == "mJoloQsGw4y-mlo2Lo3pMsesJrVna3FPQN4DuV5HaTs")
    }

    /// SHA-256(token) is the hash KyIdentity stores; a database reader must not hold K.
    @Test func keyIsNotTheStoredTokenHash() throws {
        let token = try #require(pairing.pairingToken)
        let key = try #require(pairing.proofKey)
        #expect(key.count == 32)
        #expect(key != Data(SHA256.hash(data: Data(token.utf8))))
    }

    @Test func aVerifiedReplyIsRead() throws {
        let proof = try PairingProof(pairing)
        #expect(try PairingClient.acceptedReply(answer(reply), proof: proof, request: request)["deviceId"] as? String == "dev-1")
    }

    @Test func aMissingTamperedOrMisboundReplyIsRefused() throws {
        let proof = try PairingProof(pairing)
        let tampered = Data((#"{"success":true,"deviceId":"dev-2","device":{"id":"dev-1"}}"# + "\n").utf8)
        let cases: [(HTTPResponse, Data)] = [
            (answer(nil), request),
            (answer(""), request),
            (answer("not base64url!"), request),
            (answer("A" + reply.dropFirst()), request),
            (answer(reply, body: tampered), request),
            (answer(reply, body: response.dropLast()), request),
            (answer(reply), request + Data(" ".utf8)), // a reply to another request
        ]
        for (response, request) in cases {
            #expect(throws: PairingError.invalid(PairingClient.unverifiedReply)) {
                try PairingClient.acceptedReply(response, proof: proof, request: request)
            }
        }
    }

    @Test func refusalsKeepTheirMessage() throws {
        let refusal = answer(nil, body: Data(#"{"error":"registration_failed","error_description":"Invalid token"}"#.utf8), status: 400)
        #expect(throws: PairingError.invalid("Invalid token")) {
            try PairingClient.acceptedReply(refusal, proof: try PairingProof(pairing), request: request)
        }
    }

    /// PIN pairing stays trust on first use, byte for byte as before pairing proof v1.
    @Test func pinPairingIsUnchanged() throws {
        let pin = try QrPairing(serverUrl: "https://id.example.com", pinCode: "123456", userId: "u-1")
        #expect(try PairingProof(pin) == nil)
        #expect(pin.credential == "u-1|123456")
        let body = try HTTPClient.encodeJSON(PairingClient.requestBody(
            pairing: pin, deviceName: "iPhone", deviceIdentifier: "inst-1", pushToken: "tok",
            pushKeys: try PushKeys(stored: PushVectors.receiverStored), publicKey: "BAAA", appAttest: nil
        ))
        #expect(String(decoding: body, as: UTF8.self) ==
            #"{"deviceIdentifier":"inst-1","deviceName":"iPhone","pinCode":"123456","platform":"ios","publicKey":"BAAA","# +
            #""pushAuth":"\#(PushVectors.auth)","pushP256dh":"\#(PushVectors.receiverP256dh)","pushToken":"tok","userId":"u-1"}"#)
        #expect(try PairingClient.acceptedReply(answer(nil), proof: nil, request: body)["deviceId"] as? String == "dev-1")
    }
}

@MainActor
struct PushRefreshTests {
    // Golden vectors shared with KyIdentity-server and KyAuth Android (relay transport).
    @Test func messageMatchesGoldenVector() throws {
        let message = try PushRefreshClient.message(
            serverUrl: "https://id.example.com", deviceId: "d-456", issuedAtMs: 1_791_331_200_000, pushToken: "fcm-token-1", keys: nil
        )
        #expect(String(decoding: message, as: UTF8.self) ==
            "kyidentity-push-token-v2|https://id.example.com|d-456|1791331200000|fcm|" +
            "3cfaa3f1d62d114805029366153fbb440a2d4e4b56406a04830579ac65db6a5c||")
        let sealed = try PushRefreshClient.message(
            serverUrl: "https://id.example.com", deviceId: "d-456", issuedAtMs: 1_791_331_200_000, pushToken: "fcm-token-1",
            keys: PushKeys(stored: PushVectors.receiverStored)
        )
        #expect(String(decoding: sealed, as: UTF8.self) ==
            "kyidentity-push-token-v2|https://id.example.com|d-456|1791331200000|fcm|" +
            "3cfaa3f1d62d114805029366153fbb440a2d4e4b56406a04830579ac65db6a5c|" +
            "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4|BTBZMqHH6r4Tts7J_aSIgg")
    }

    @Test func refusesSeparatorAndSendsWebPushKeysOnlyWhenPaired() throws {
        #expect(throws: PairingError.self) {
            try PushRefreshClient.message(serverUrl: "https://id.example.com", deviceId: "d|1", issuedAtMs: 1, pushToken: "t", keys: nil)
        }
        let body = PushRefreshClient.requestBody(pushToken: "t", keys: nil, issuedAtMs: 7, signature: Data([1, 2]))
        #expect(body["pushTransport"] as? String == "fcm")
        #expect(body["issuedAt"] as? Int64 == 7)
        #expect(body["signature"] as? String == "AQI=")
        #expect(body["pushP256dh"] == nil)
        #expect(body["pushAuth"] == nil)
        let sealed = PushRefreshClient.requestBody(
            pushToken: "t", keys: try PushKeys(stored: PushVectors.receiverStored), issuedAtMs: 7, signature: Data([1, 2])
        )
        #expect(sealed["pushP256dh"] as? String == PushVectors.receiverP256dh)
        #expect(sealed["pushAuth"] as? String == PushVectors.auth)
    }

    @Test func tokenIsLowercaseHexAndRefreshFollowsRotation() {
        #expect(PushStore.hex(Data([0x0a, 0xff])) == "0aff")
        var state = PushState(latestToken: "a", registeredToken: "a")
        #expect(!state.needsRefresh(paired: true))
        state.latestToken = "b"
        #expect(state.needsRefresh(paired: true))
        #expect(!state.needsRefresh(paired: false))
    }
}

@MainActor
struct AttestationReasonTests {
    @Test func classify() {
        #expect(AttestationReason.classify(level: "appattest", serverReportedLevel: true, attested: true) == "")
        #expect(AttestationReason.classify(level: "none", serverReportedLevel: false, attested: true) == "server-unsupported")
        #expect(AttestationReason.classify(level: "none", serverReportedLevel: true, attested: false) == "app-attest-unavailable")
        #expect(AttestationReason.classify(level: "none", serverReportedLevel: true, attested: true) == "not-accepted")
    }
}
