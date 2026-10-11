import CryptoKit
import DeviceCheck
import Foundation

/// The `appAttest` request member: Apple's attestation that this pairing request, including its
/// device public key, was built by a genuine KyAuth. See docs/specs/2026-10-11-ios-app-attest.md.
struct AppAttestation: Equatable {
    let keyId: String
    let attestation: String
}

enum AppAttestor {
    private static let prefix = "kyidentity-appattest-v1|"

    /// The exact bytes KyIdentity recomputes; `publicKey` is the request's `publicKey` string.
    static func clientData(credential: String, publicKey: String) -> Data {
        Data((prefix + credential + "|" + publicKey).utf8)
    }

    /// Nil when App Attest is unavailable (simulator, older hardware) or fails: attestation never
    /// fails a pairing, the server just grades it `none`.
    static func attest(credential: String, publicKey: String) async -> AppAttestation? {
        let service = DCAppAttestService.shared
        guard service.isSupported else { return nil }
        do {
            let keyId = try await service.generateKey()
            let hash = Data(SHA256.hash(data: clientData(credential: credential, publicKey: publicKey)))
            let object = try await service.attestKey(keyId, clientDataHash: hash)
            return AppAttestation(keyId: keyId, attestation: object.base64EncodedString())
        } catch {
            return nil
        }
    }
}

/// Why a pairing ended up ungraded, so Settings can say whether pairing again can help.
enum AttestationReason {
    static let none = ""
    static let serverUnsupported = "server-unsupported"
    static let appAttestUnavailable = "app-attest-unavailable"
    static let notAccepted = "not-accepted"

    static func classify(level: String, serverReportedLevel: Bool, attested: Bool) -> String {
        if level != "none" { return none }
        if !serverReportedLevel { return serverUnsupported }
        if !attested { return appAttestUnavailable }
        return notAccepted
    }

    static func summary(level: String, reason: String) -> String {
        if level == "appattest" { return "Verified by App Attest" }
        switch reason {
        case serverUnsupported: return "Not verified: this KyIdentity does not check iOS devices yet"
        case appAttestUnavailable: return "Not verified: App Attest is unavailable on this device"
        case notAccepted: return "Not verified: KyIdentity did not accept this device's App Attest"
        default: return "Not verified"
        }
    }
}
