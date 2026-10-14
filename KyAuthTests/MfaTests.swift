import Foundation
import Testing
@testable import KyAuth

@MainActor
struct MfaMessageTests {
    private func message(_ purpose: String, _ approve: Bool, _ digits: String) throws -> String {
        String(decoding: try MfaMessage.payload(
            origin: "https://id.example.com", userId: "u-123", deviceId: "d-456", challengeId: "c-789",
            purpose: purpose, expiresAtMs: 1_791_331_200_000, approve: approve, selectedDigits: digits
        ), as: UTF8.self)
    }

    // Golden vectors shared with KyIdentity-server and KyAuth Android.
    @Test func goldenVectors() throws {
        #expect(try message("login", true, "42") ==
            "kyidentity-push-v2|https://id.example.com|u-123|d-456|c-789|login|1791331200000|approve|42")
        #expect(try message("step_up", false, "") ==
            "kyidentity-push-v2|https://id.example.com|u-123|d-456|c-789|step_up|1791331200000|deny|")
    }

    @Test func refusesAmbiguousFields() {
        #expect(throws: PairingError.self) { try message("session", true, "42") }
        #expect(throws: PairingError.self) {
            try MfaMessage.payload(origin: "https://id.example.com", userId: "u|1", deviceId: "d", challengeId: "c",
                                   purpose: "login", expiresAtMs: 1, approve: true, selectedDigits: "42")
        }
        #expect(throws: PairingError.self) {
            try MfaMessage.payload(origin: "https://id.example.com", userId: "", deviceId: "d", challengeId: "c",
                                   purpose: "login", expiresAtMs: 1, approve: true, selectedDigits: "42")
        }
    }

    @Test func originVectors() throws {
        #expect(try MfaMessage.origin("https://ID.Example.com/") == "https://id.example.com")
        #expect(try MfaMessage.origin("https://id.example.com:443") == "https://id.example.com")
        #expect(try MfaMessage.origin("https://id.example.com:8443/kyidentity") == "https://id.example.com:8443")
        #expect(try MfaMessage.origin("http://127.0.0.1:8080") == "http://127.0.0.1:8080")
        #expect(try MfaMessage.origin("https://[::1]") == "https://[::1]")
        #expect(try MfaMessage.origin("https://[::1]:8443/x") == "https://[::1]:8443")
        #expect(throws: PairingError.self) { try MfaMessage.origin("not a url") }
    }

    @Test func twoDigits() {
        #expect(MfaMessage.isTwoDigits("07"))
        #expect(!MfaMessage.isTwoDigits("7"))
        #expect(!MfaMessage.isTwoDigits("123"))
        #expect(!MfaMessage.isTwoDigits("٤٢"))
    }
}

@MainActor
struct MfaPushParserTests {
    let paired = PairedAccount(serverUrl: "https://id.example.com", deviceId: "d-1", deviceName: "iPhone", userId: "u-1")
    let now = Date(timeIntervalSince1970: 1_000_000)
    var nowMs: Int64 { 1_000_000_000 }

    func push(_ overrides: [String: String] = [:], removing: [String] = []) -> [AnyHashable: Any] {
        var data: [String: String] = [
            "type": "mfa_challenge", "challengeId": "c-1", "deviceId": "d-1", "deviceUserId": "u-1",
            "purpose": "login", "expiresAtEpochMs": String(nowMs + 60_000),
            "aps": "ignored", "serverUrl": "https://evil.example.com",
        ]
        data.merge(overrides) { $1 }
        for key in removing { data.removeValue(forKey: key) }
        return data
    }

    @Test func parsesKyIdentityPushAndIgnoresPayloadServer() throws {
        let challenge = try MfaPushParser.parse(push(), paired: paired, now: now)
        #expect(challenge.challengeId == "c-1")
        #expect(challenge.serverUrl == "https://id.example.com")
        #expect(challenge.purposeText == "Sign in")
    }

    /// KyIdentity's push names no user, so the card names the paired account; a payload name wins.
    @Test func namesThePairedAccount() throws {
        var named = paired
        named.username = "alice"
        #expect(try MfaPushParser.parse(push(), paired: named, now: now).username == "alice")
        #expect(try MfaPushParser.parse(push(["username": "bob"]), paired: named, now: now).username == "bob")
        #expect(try MfaPushParser.parse(push(), paired: paired, now: now).username == nil)
    }

    @Test func refusesForeignDeviceAccountPurposeAndExpiry() {
        for bad in [
            push(["deviceId": "d-2"]), push(["deviceUserId": "u-2"]), push(removing: ["deviceUserId"]),
            push(["purpose": "session"]), push(removing: ["purpose"]),
            push(["expiresAtEpochMs": String(nowMs - 1)]), push(removing: ["expiresAtEpochMs"]),
            push(["expiresAtEpochMs": String(nowMs + 10 * 60 * 1000 + 1)]),
            push(removing: ["challengeId"]),
        ] {
            #expect(throws: PairingError.self) { try MfaPushParser.parse(bad, paired: paired, now: now) }
        }
        #expect(throws: PairingError.self) { try MfaPushParser.parse(push(), paired: nil, now: now) }
        var noUser = paired
        noUser.userId = nil
        #expect(throws: PairingError.self) { try MfaPushParser.parse(push(), paired: noUser, now: now) }
    }

    /// The phone never holds the answer: match or decoy numbers in a payload are dropped, so the
    /// stored challenge cannot show them.
    @Test func answerDigitsInAPayloadAreIgnored() throws {
        let challenge = try MfaPushParser.parse(
            push(["matchDigits": "42", "decoyDigits": "11,88,55"]), paired: paired, now: now
        )
        let stored = String(decoding: try JSONEncoder().encode(challenge), as: UTF8.self)
        #expect(!stored.contains("Digits"))
    }

    @Test func countdown() {
        let challenge = MfaChallenge(challengeId: "c", serverUrl: "s", purpose: "step_up", expiresAtEpochMs: 10_500)
        #expect(challenge.secondsRemaining(now: Date(timeIntervalSince1970: 10)) == 1)
        #expect(challenge.isExpired(now: Date(timeIntervalSince1970: 10.5)))
        #expect(challenge.purposeText == "Confirm a sensitive action")
    }
}

@MainActor
struct MfaResponseTests {
    @Test func aDecisionIsRequired() {
        #expect(MfaResponseClient.parse(status: 200, json: ["success": true], errorText: nil, challengeId: "c") == .success(approved: true))
        #expect(MfaResponseClient.parse(status: 200, json: ["approved": false], errorText: nil, challengeId: "c") == .success(approved: false))
        #expect(MfaResponseClient.parse(status: 200, json: [:], errorText: nil, challengeId: "c") == .error("Server did not report a decision"))
        #expect(MfaResponseClient.parse(status: 200, json: ["challengeId": "x", "success": true], errorText: nil, challengeId: "c")
            == .error("Server answered a different challenge"))
        #expect(MfaResponseClient.parse(status: 400, json: [:], errorText: "Challenge could not be answered", challengeId: "c")
            == .error("Challenge could not be answered"))
    }
}
