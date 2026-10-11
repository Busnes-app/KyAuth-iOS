# KyAuth iOS: App Attest grading at pairing

Status: approved direction (user, 2026-10-11: "add App Attest to KyIdentity").
Wire contract between KyAuth iOS and `KyIdentity-server`.

## Why

KyIdentity grades Android pairings from a Keystore attestation chain (`none`/`tee`/`strongbox`).
An ungraded device gets `amr:["pop"]` from the device-assertion grant and is refused
(`signon_not_permitted`) by any app policy other than `reuse`. iOS has no key attestation for
arbitrary Secure Enclave keys. App Attest proves the request was built by a genuine, unmodified
KyAuth on a genuine Apple device; that build always creates its device signing key in the Secure
Enclave with `.privateKeyUsage` + `.userPresence`. The grade therefore rests on app integrity, not
on a statement about the key itself. This is weaker evidence than Android's chain and is graded
under its own level, `appattest`.

## Client (KyAuth iOS)

At every pairing, after the new device signing key exists:

1. `keyId = DCAppAttestService.shared.generateKey()` (a fresh App Attest key per pairing).
2. `clientData = "kyidentity-appattest-v1|" + credential + "|" + publicKey`
   - `credential`: the pairing token, else `userId + "|" + pinCode` (same rule as Android's
     `kyidentity-attest-v1` challenge).
   - `publicKey`: the exact `publicKey` string sent in the request: standard padded base64 of
     the signing key's SPKI DER.
3. `attestation = attestKey(keyId, clientDataHash: SHA256(clientData))`.
4. The registration request adds
   `"appAttest": {"keyId": <keyId as returned>, "attestation": <standard base64 of the object>}`.

When App Attest is unsupported (simulator, old hardware) or any step fails, `appAttest` is
omitted and pairing continues. Attestation never fails a pairing.

## Server (KyIdentity)

Graded only when `platform == "ios"` and `appAttest` is present and App Attest is configured;
otherwise `none`. Android chains are graded only for `platform == "android"`.

Verification (Apple, "Validating apps that connect to your server"):

1. CBOR-decode the attestation object: `fmt == "apple-appattest"`, `attStmt.x5c` (leaf first),
   `authData`.
2. Verify `x5c` to the pinned Apple App Attestation Root CA
   (SHA-256 `1CB9823BA28BA6AD2D33A006941DE2AE4F513EF1D4E831B9F7E0FA7B6242C932`) at the current time.
3. Recompute `clientData` from the request (`publicKey` as sent) and
   `nonce = SHA256(authData || SHA256(clientData))`. It must equal the leaf extension
   `1.2.840.113635.100.8.2` (`SEQUENCE { [1] EXPLICIT OCTET STRING }`).
4. `SHA256(leaf public key, uncompressed X9.63 point) == base64decode(keyId)`.
5. `authData.rpIdHash == SHA256(appId)` for a configured App ID (`<TeamID>.<bundleID>`).
6. `authData.signCount == 0`.
7. `authData.aaguid` is `"appattest" + 7 × 0x00` (production), or `"appattestdevelop"` only when
   development is enabled.
8. `authData.credentialId == base64decode(keyId)`.
9. The `publicKey` in the request parses as a P-256 key (already required).

Pass: `attestedLevel = "appattest"`, `bootState = "unknown"`. Any failure: `none`, logged with the
reason, never echoed to the client.

Configuration:

- `KYIDENTITY_APPATTEST_APP_IDS`: comma-separated `<TeamID>.<bundleID>`; empty disables grading.
  KyAuth iOS is `TATYN4X57D.org.kysecurity.authenticator`.
- `KYIDENTITY_APPATTEST_ALLOW_DEVELOPMENT`: `true` accepts the `appattestdevelop` AAGUID (debug
  and TestFlight-sandbox builds). Default `false`.

Consumers of the level:

- `appattest` is a valid stored level alongside `none`, `tee`, `strongbox`.
- The device-assertion grant treats `appattest` as attested (MFA-grade `amr`/`acr`).
- The attestation sweep skips `appattest` devices: there are no certificate serials to revoke,
  and `RequireLockedBootloader` is an Android boot-state rule that iOS cannot report.

## Response

Unchanged shape: `device.attestedLevel` may now be `appattest`. KyAuth iOS shows
"Verified by App Attest"; `none` with a reason (server did not grade, App Attest unavailable on
this device, or not accepted) as on Android.
