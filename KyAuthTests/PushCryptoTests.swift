import Foundation
import Testing
@testable import KyAuth

enum PushVectors {
    // RFC 8291 section 5: the receiver's private key, public key and auth secret.
    static let receiverPrivate = "q1dXpw3UpT5VOmu_cf_v6ih07Aems3njxI-JWgLcM94"
    static let receiverP256dh = "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
    static let auth = "BTBZMqHH6r4Tts7J_aSIgg"
    static var receiverStored: Data { Base64URL.decode(receiverPrivate)! + Base64URL.decode(auth)! }

    // RFC 8291 appendix A: the encrypted body of "When I grow up, I want to be a watermelon".
    static let rfcBody = "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml" +
        "mlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPT" +
        "pK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN"

    // KyIdentity's RelaySender output for the receiver above: challengeData for device dev-1, user
    // user-1, challenge ch-1, purpose step_up, expiry 1791331200000, sealed by webPushEncrypt into
    // its fixed 640-byte record (968 characters, under the relay's 1024).
    static let serverSealed = "d33DjOr9uO2oM7mddWPOWAAAAoBBBItc_L_nZrU3cfOUtB9bJioq9m6I3zMq4q0NPJe6LPUC3GIqIlT4aN9q8wJIHXEU6yV3" +
        "y8cmaV5HBtWvmNUwPOsbUf5LoRA3NOmyvJcRDABvPtaubVBJGIniwIu5fW3CgPaZIDrQaz2nEvVbJqStd8iRuEpDoZq7icd8jgkZT4gzY0wdVGwFMC4P" +
        "ki2_lWltLAz29alnTbbXLIG6pgTCORMk7EgOfEhf5a9quDgmEA151BIUvVgPl1AuNuFKnmyX48Obs3vb7keNlZZ25m9nRYe2I5RQEUj40IpKWOZX9yqA" +
        "0i7UrukRCRHgBF_MryFAWA3dOpQHIIXk0tod1xek_ZQkhgOIeg6m9pX2VDz8y1dryPRH9d6KXOewRIBEbi4rZvNm330ANRGuSXimOAqclcEHvArRatzg" +
        "loBB8LiYwosnXhpsjUvHwDOzGkW4GPlzRNIIBtLJzcCWoFSNu1KD-1AMAo3uBPmgG9UCi1g5OLd6K8_mkn_njMh_9_BSbjrf6kTiVoITgZ7cQSPEq6Uf" +
        "E8C0MJnL8uVvmy9cTpwBcfhQLDNOO21jFE4w2znDk9JnutWTF0A6QExhxLXmtmAyof19XOzNAHgq8NJ27kPDwqc85A2RbxbSBKPV34i5aXw-hwdtBxqe" +
        "02HrWy01gILm-SDh7u6SutG3QPgnO8zgjnPLz-KB5WMJC-6ybBt-L4X5MXH9eFpjxC2CHDLU_4OU9X-2qIK-QfhOY-6xQt5fOq7MG53QoqWg9Q0DwxoH" +
        "p8y_HTB7-EHbrYB7ukroZAbso9gPKsZZaWlFZ-0xE6BiEHgSE1IzZ28s10UHoRhvYGCTa2A6-rquFY4Jh8uTjaiWZCUrIgkHVY_TlDwnKsS-i2Ax0G5Q" +
        "9cQUu7upBB5-7EY3yg2IYN5AvqnvmN1BEkU58T2cG_YgWJfThuXUgIYavjvv"
}

struct WebPushTests {
    private let keys = try! PushKeys(stored: PushVectors.receiverStored)
    private var body: Data { Base64URL.decode(PushVectors.rfcBody)! }

    @Test func decryptsRfc8291Example() throws {
        #expect(keys.p256dh == PushVectors.receiverP256dh)
        #expect(keys.authSecret == PushVectors.auth)
        let plain = try WebPush.decrypt(body, keys: keys)
        #expect(String(decoding: plain, as: UTF8.self) == "When I grow up, I want to be a watermelon")
    }

    @Test func refusesTamperingAndOtherKeys() throws {
        var flipped = body
        flipped[flipped.count - 20] ^= 1
        #expect(throws: (any Error).self) { try WebPush.decrypt(flipped, keys: keys) }
        let otherAuth = PushKeys(privateKey: keys.privateKey, auth: Data(repeating: 7, count: 16))
        #expect(throws: (any Error).self) { try WebPush.decrypt(body, keys: otherAuth) }
        #expect(throws: (any Error).self) { try WebPush.decrypt(body, keys: .generate()) }
        #expect(throws: (any Error).self) { try WebPush.decrypt(body.prefix(100), keys: keys) }
    }

    @Test func refusesMoreThanOneRecord() {
        var split = body
        split[16..<20] = Data([0, 0, 0, 32]) // record size 32, but the record is 58 bytes
        #expect(throws: (any Error).self) { try WebPush.decrypt(split, keys: keys) }
    }

    @Test func generatedKeysSurviveTheKeychainForm() throws {
        let generated = PushKeys.generate()
        let restored = try PushKeys(stored: generated.stored)
        #expect(restored.p256dh == generated.p256dh)
        #expect(restored.authSecret == generated.authSecret)
        #expect(Base64URL.decode(generated.p256dh)?.count == 65)
        #expect(generated.auth.count == 16)
        #expect(!generated.p256dh.contains("=") && !generated.authSecret.contains("="))
        #expect(throws: (any Error).self) { try PushKeys(stored: Data(count: 47)) }
    }
}

@MainActor
struct PushPayloadTests {
    private let keys = try! PushKeys(stored: PushVectors.receiverStored)
    private let paired = PairedAccount(serverUrl: "https://id.example.com", deviceId: "dev-1", deviceName: "iPhone", userId: "user-1")
    private let plaintext: [AnyHashable: Any] = [
        "type": "mfa_challenge", "deviceId": "dev-1", "deviceUserId": "user-1", "challengeId": "ch-1",
        "purpose": "login", "expiresAtEpochMs": "1791331200000",
    ]

    /// The whole receive path against KyIdentity's own sealing.
    @Test func opensServerSealedChallenge() throws {
        let push: [AnyHashable: Any] = ["aps": ["alert": ["title": "Sign-in request"]], "type": "mfa_challenge", "kyauth": PushVectors.serverSealed]
        let fields = try PushPayload.fields(push, keys: keys)
        #expect(fields["type"] as? String == "mfa_challenge")
        let challenge = try MfaPushParser.parse(fields, paired: paired, now: Date(timeIntervalSince1970: 1_791_331_140))
        #expect(challenge.challengeId == "ch-1")
        #expect(challenge.purpose == "step_up")
        #expect(challenge.expiresAtEpochMs == 1_791_331_200_000)
        #expect(challenge.username == nil)
    }

    @Test func pairingWithKeysRefusesPlaintext() {
        #expect(throws: PushPayloadError.self) { try PushPayload.fields(plaintext, keys: keys) }
    }

    @Test func pairingWithoutKeysReadsPlaintextButNotSealed() throws {
        #expect(try PushPayload.fields(plaintext, keys: nil)["challengeId"] as? String == "ch-1")
        #expect(throws: PushPayloadError.self) {
            try PushPayload.fields(["type": "mfa_challenge", "kyauth": PushVectors.serverSealed], keys: nil)
        }
    }

    @Test func refusesUnreadableSealedPayload() {
        #expect(throws: (any Error).self) { try PushPayload.fields(["kyauth": "not base64url!"], keys: keys) }
        #expect(throws: (any Error).self) { try PushPayload.fields(["kyauth": PushVectors.rfcBody], keys: keys) } // not JSON
    }

    @Test func alertTextIsFixed() {
        #expect(PushPayload.alertTitle(purpose: "step_up") == "Confirm a sensitive action")
        #expect(PushPayload.alertTitle(purpose: "login") == "Sign-in request")
        #expect(PushPayload.alertTitle(purpose: nil) == "Sign-in request")
        #expect(PushPayload.alertBody == "Open KyAuth to review.")
    }
}
