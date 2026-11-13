//
//  FuzzScannedCode.swift
//  KyAuth fuzzing
//
//  libFuzzer entry point for ScannedCode.parse, which takes whatever the
//  Codes tab's camera read from a QR code: an `otpauth://` setup code, a
//  KyIdentity pairing link, or pairing JSON. Anyone who can put a QR code in
//  front of the camera chooses every byte. The other Swift files in this
//  directory are symlinks to the app's own sources.
//
//  Besides crashes and sanitizer reports, it traps when a value the parser
//  accepted breaks a rule the app relies on afterwards.
//

import Foundation

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzScannedCode(_ start: UnsafeRawPointer, _ count: Int) -> CInt {
    let raw = String(decoding: Data(bytes: start, count: count), as: UTF8.self)

    switch try? ScannedCode.parse(raw, now: now) {
    case .account(let entry)?:
        // The app shows a code for a new account at once.
        precondition(TotpGenerator.isUsableSecret(entry.secretBase32), "accepted an unusable secret")
        let code = try? TotpGenerator.code(entry, at: Int64(now.timeIntervalSince1970))
        precondition(code?.count == entry.digits, "code length differs from digits")
    case .pairing(let pairing)?:
        // A pairing is only accepted for an HTTPS server, with every endpoint
        // KyAuth calls buildable from it.
        precondition((try? PairingEndpoint.registrationUrl(pairing.serverUrl))?.scheme == "https",
                     "accepted a pairing without an HTTPS registration endpoint")
        precondition((try? PairingEndpoint.validatedRegistrationUrl(pairing.serverUrl, pairing.registrationUrl)) != nil,
                     "accepted a registration URL that no longer validates")
    case nil:
        break
    }
    return 0
}
