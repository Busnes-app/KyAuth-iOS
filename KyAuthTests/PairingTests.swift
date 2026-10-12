import CryptoKit
import Foundation
import Testing
@testable import KyAuth

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
        #expect(pairing.credential == "pt-1")
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
            try QrPairingParser.parse(#"{"type":"other","serverUrl":"https://id.example.com","pairingToken":"t"}"#)
        }
        #expect(throws: PairingError.self) {
            try QrPairingParser.parse(#"{"type":"kyidentity_device_pairing","serverUrl":"https://id.example.com","pairingToken":"t","expiresAt":1}"#)
        }
        #expect(throws: PairingError.self) {
            try QrPairingParser.parse(#"{"type":"kyidentity_device_pairing","serverUrl":"http://id.example.com","pairingToken":"t"}"#)
        }
        #expect(throws: PairingError.self) {
            try QrPairingParser.parse("kyidentity://native-pair?srv=https%3A%2F%2Fid.example.com&pin=1")
        }
        #expect(throws: PairingError.self) { try QrPairingParser.parse("https://example.com") }
    }

    @Test func registrationUrlMustShareOrigin() throws {
        #expect(throws: PairingError.self) {
            try QrPairingParser.parse(#"{"type":"kyidentity_device_pairing","serverUrl":"https://id.example.com","registrationUrl":"https://evil.example.com/api/notifications/native/register","pairingToken":"t"}"#)
        }
        let ok = try PairingEndpoint.validatedRegistrationUrl(
            "https://id.example.com", "https://ID.example.com:443/api/notifications/native/register"
        )
        #expect(ok.host() == "ID.example.com")
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

    @Test func requestAlwaysNamesIosAndCarriesAppAttest() {
        let body = PairingClient.requestBody(
            pairing: pairing, deviceName: " Ada's iPhone ", deviceIdentifier: "inst-1", pushToken: "abcd",
            publicKey: "PK", appAttest: AppAttestation(keyId: "kid", attestation: "obj")
        )
        #expect(body["platform"] as? String == "ios")
        #expect(body["deviceName"] as? String == "Ada's iPhone")
        #expect(body["pushToken"] as? String == "abcd")
        #expect(body["pairingToken"] as? String == "pt")
        #expect(body["pushTransport"] == nil)
        #expect((body["appAttest"] as? [String: String]) == ["keyId": "kid", "attestation": "obj"])
        let plain = PairingClient.requestBody(
            pairing: pairing, deviceName: "x", deviceIdentifier: "i", pushToken: "t", publicKey: "PK", appAttest: nil
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

@MainActor
struct PushRefreshTests {
    // Golden vector shared with KyIdentity-server and KyAuth Android (relay transport, no Web Push keys).
    @Test func messageMatchesGoldenVector() throws {
        let message = try PushRefreshClient.message(
            serverUrl: "https://id.example.com", deviceId: "d-456", issuedAtMs: 1_791_331_200_000, pushToken: "fcm-token-1"
        )
        #expect(String(decoding: message, as: UTF8.self) ==
            "kyidentity-push-token-v2|https://id.example.com|d-456|1791331200000|fcm|" +
            "3cfaa3f1d62d114805029366153fbb440a2d4e4b56406a04830579ac65db6a5c||")
    }

    @Test func refusesSeparatorAndOmitsWebPushKeys() {
        #expect(throws: PairingError.self) {
            try PushRefreshClient.message(serverUrl: "https://id.example.com", deviceId: "d|1", issuedAtMs: 1, pushToken: "t")
        }
        let body = PushRefreshClient.requestBody(pushToken: "t", issuedAtMs: 7, signature: Data([1, 2]))
        #expect(body["pushTransport"] as? String == "fcm")
        #expect(body["issuedAt"] as? Int64 == 7)
        #expect(body["signature"] as? String == "AQI=")
        #expect(body["pushP256dh"] == nil)
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
