# Assurance case

[Product overview](../README.md) · [App contracts](../KyAuth/AGENTS.md) · [Verifying releases](VERIFYING-RELEASES.md)

This is the argument that KyAuth for iOS meets its security requirements: what it protects, from
whom, where the trust boundaries are, and why the design and the code hold at each one. The
detailed contracts live in [KyAuth/AGENTS.md](../KyAuth/AGENTS.md) and [docs/specs/](specs/).
Paths are relative to the repository root.

## What KyAuth must protect

KyAuth is an authenticator: it holds TOTP secrets, and a device key that KyIdentity trusts to
approve sign-ins. Its security requirements:

1. **Only the phone's owner can approve a sign-in.** An approval needs the device key, which
   never leaves the Secure Enclave, a Face ID or passcode check, and the two digits the browser
   shows.
2. **TOTP secrets stay on this device** and readable only after a Face ID or passcode check.
   No backup, export or sync.
3. **Answers go only to the paired server.** Nothing in a push or a QR code can redirect an
   answer or a token elsewhere.
4. **The push path learns nothing useful and cannot inject requests.** APNs and the relay see
   only ciphertext; a pairing with push keys refuses plaintext pushes.
5. **Only listed suite apps get an ID token** through the sign-on handoff, and only for the
   paired KyIdentity.
6. **Losing the phone does not hand over the vault.** Locking, the optional PIN with its wipe,
   and this-device-only Keychain items.

## Threat model

| Attacker | Can | Wants |
|---|---|---|
| Network attacker | Read and alter traffic between the phone and KyIdentity | Steal tokens, forge answers |
| APNs, the push relay | See and replay push traffic | Learn who signs in where; trick the user into approving |
| Malicious QR code or link | Put any server URL, token or registration URL in front of the user | Pair KyAuth with an attacker's server or send answers there |
| Another app on the phone | Open `kyauth://` links; write to an App Group only if it is from team `TATYN4X57D` | Get an ID token, read codes |
| Someone holding an unlocked or stolen phone | Open the app, try PINs | Read TOTP codes, approve a sign-in |
| Device backup or a later install | Read restored files and Keychain items | Recover the vault or the pairing |

Out of scope: a jailbroken or otherwise compromised iOS, and an attacker who knows the device
passcode and holds the phone. iOS protections are the foundation this app builds on.

## Trust boundaries

1. **Phone → KyIdentity.** HTTPS only in release builds (`KyAuth/Pairing/PairingEndpoint.swift`,
   `isAllowedScheme`). Every endpoint is built from the paired server URL, and the one URL a QR
   code may name, the registration URL, must have the same origin. Redirects are refused, and
   nothing is cached or kept in cookies (`KyAuth/Networking/HTTPClient.swift`). The
   native server trust is evaluated without replacing its policies or anchors, then
   every certificate in its built chain must expose actual RSA>=2048 or prime EC>=256
   key bits. This includes a root omitted from the wire and a directly trusted peer;
   missing/unknown metadata refuses the challenge. RSA block bytes are not bit size.
2. **APNs and the relay → phone.** Pushes are RFC 8291 `aes128gcm` sealed to a key pair made on
   the phone (`Shared/PushCrypto.swift`). The notification extension shows only fixed text.
   The app re-opens and checks every push itself (`KyAuth/Mfa/MfaChallenge.swift`, `MfaPushParser`).
3. **Suite app → KyAuth (sign-on handoff).** Requests arrive as files in App Group
   `group.org.kysecurity.signon`, which only team `TATYN4X57D` apps can write. KyAuth then
   checks the consumer against `TrustedConsumers`, the age, client ID, origin and issuer
   (`KyAuth/SignOn/SignOnHandoff.swift`).
4. **App → its storage.** The vault is an AES-256-GCM file excluded from backup. Its key and
   every other Keychain item are this-device-only and never synced (`Shared/Keychain.swift`).

## Secure design principles applied

- **Least privilege.** The notification extension holds only the push-key access group,
  `group.org.kysecurity.authenticator.push`; every other item stays in KyAuth's own group.
  Push MFA and sign-on never touch the vault key.
- **Fail-safe defaults.** An unknown purpose, a foreign device or account, or an expiry that is
  missing or more than ten minutes ahead refuses the push instead of defaulting it. App Attest
  failing leaves a pairing ungraded, never upgraded.
- **Complete mediation.** Each signature and each vault unlock needs its own Face ID or passcode
  check (`KyAuth/Security/UserPresence.swift`).
- **Economy of mechanism.** No third-party packages: the Xcode project references none, and
  all cryptography is Apple's CryptoKit, CommonCrypto and Security frameworks.
- **Separation of privilege.** Approving needs both the device key (Face ID or passcode) and the
  digits from the browser. The phone never holds the answer.
- **Open design.** Only published algorithms and formats: AES-GCM, P-256 ECDSA and ECDH, HKDF,
  PBKDF2, RFC 6238 TOTP, RFC 8291 Web Push, RFC 7523 assertions.

## Common weaknesses and how they are countered

| Weakness | Counter | Where |
|---|---|---|
| Push approval fatigue and spoofed requests | The user types the two digits the browser shows; match or decoy numbers in a payload are dropped | `KyAuth/Mfa/MfaChallenge.swift` (`MfaPushParser`) |
| Push injection or reading by APNs or the relay | Pushes sealed to per-pairing keys; a pairing with keys refuses plaintext pushes | `Shared/PushCrypto.swift` (`PushPayload.fields`) |
| Answer redirection through a payload or QR code | A payload `serverUrl` is ignored; a QR registration URL must share the server's origin; HTTPS only in release builds | `MfaPushParser`, `KyAuth/Pairing/PairingEndpoint.swift` |
| Undersized TLS authentication keys | Normal SecTrust evaluation plus actual-bit checks on every evaluated certificate/anchor; no weak-key override | `KyAuth/Networking/HTTPClient.swift` (`TransportPolicy`) |
| Open redirect, response caching | URLSession refuses redirects; ephemeral session, no cookies, no URL cache | `KyAuth/Networking/HTTPClient.swift` |
| Signed-message ambiguity | Every field of the signed answer is checked for the `\|` separator and the purpose against a fixed set | `MfaMessage.payload` |
| Device key theft | Secure Enclave P-256, `.privateKeyUsage` and `.userPresence`, passcode required, replaced at every pairing | `KyAuth/Pairing/DeviceSigningKey.swift` |
| Secrets at rest | Vault AES-256-GCM with a fixed associated-data label; key released only by user presence; file excluded from backup and written with complete file protection | `KyAuth/Totp/TotpVault.swift` |
| Secrets restored to another device or reinstall | Keychain items `ThisDeviceOnly` and non-synchronizable; a fresh install deletes leftovers | `Shared/Keychain.swift`, `KyAuth/Security/LocalWipe.swift` |
| PIN guessing | PBKDF2-HMAC-SHA256, 310,000 iterations, random 16-byte salt, constant-time compare; delays on system uptime; the fifth failure erases all data | `KyAuth/Security/PinPolicy.swift` |
| Token theft through the sign-on handoff | Consumer allow-list, single-use request file, nonce format, 120 s age limit, issuer must equal the paired server | `KyAuth/SignOn/SignOnHandoff.swift` |
| Malformed `otpauth://` input | Defaults only for omitted parameters; unsupported or malformed algorithm, digits or period refused | `KyAuth/Totp/TotpEntry.swift` |
| Keyloggers, shoulder surfing | Third-party keyboards refused app-wide; a cover over the app switcher and screen capture | `KyAuth/App/KyAuthApp.swift`, `KyAuth/UI/RootView.swift` |
| Secrets in logs | The app has no logging calls (`print`, `os_log`, `Logger`, `NSLog`) | whole source tree |
| Weak randomness | Keys and salts come from CryptoKit, the Secure Enclave and `SecRandomCopyBytes` | `TotpVault`, `PushKeys.generate`, `PinStore.set` |

TOTP uses HMAC-SHA-1 by default because RFC 6238 and nearly every site that issues codes
require it. HMAC-SHA-1 is not affected by SHA-1's collision weakness. SHA-256 and SHA-512 are
accepted when the setup code asks for them.

## Residual risk

- No backup, by design: losing the phone, or removing its passcode, loses the codes. The README
  says so first.
- The developer-run APNs relay receives the push token and, for a pairing made before push keys
  existed, KyIdentity's IDs in plaintext (`Distribution/AppStore/app-privacy.md`).
- On hardware, encrypted pushes and the notification extension are not yet observed;
  plaintext delivery through the real relay was (`KyAuth/AGENTS.md`, Verification).
- CI configures the complete native simulator suite on pushes and pull requests
  to `master` (`.github/workflows/tests.yml`); CodeQL scans Swift and workflows.
  As of 2026-10-27, coverage export, warnings-as-errors and the Release build are
  configured but await their first native CI result. Swift 5 mode without complete
  concurrency diagnostics leaves OpenSSF `warnings_strict` unverified. Hardware-only
  paths remain outside the simulator suite.
- No independent security audit has taken place.

## Evidence

- **Tests:** `KyAuthTests` covers pairing and endpoint validation, push parsing and the signed
  message, RFC 8291 vectors, sign-on handoff validation, TOTP, the vault and the PIN policy.
  Without Xcode, `scripts/check-push-crypto-linux.sh` runs the push crypto vectors against
  swift-crypto. The runner is configured to retain `coverage.json` (`xcrun xccov`)
  only after successful native tests, stats and coverage export, requiring exactly
  one usable `KyAuth.app` target. Failed tests and incomplete runs use explicitly
  named artifacts when a usable report exists; invalid/failed exports are removed
  and fail the job even if tests passed. The extension is reported as absent,
  unexercised or with its
  separate line counts. First native measurement is pending as of 2026-10-27.
  Shared sources compile into both products; their counts are not additive.
  Commit a dated coverage assessment here, citing the run and commit,
  before using these artifacts for an answer. Line counts alone do not establish
  branch, input or requirement coverage.
- **Contracts:** wire formats shared with KyIdentity are byte-exact and covered by golden
  vectors ([KyAuth/AGENTS.md](../KyAuth/AGENTS.md)).
- **Review:** every change lands through a pull request.
- **Releases:** signed by Apple; App Attest lets KyIdentity tell a genuine build
  ([VERIFYING-RELEASES.md](VERIFYING-RELEASES.md)).

This case is updated when a trust boundary or a security requirement changes. A pull request
that moves one must update this page in the same change.

## TOTP key floor and legacy data

`KyAuth/Totp/TotpEntry.swift` requires at least 16 decoded key bytes for imports and
before every HMAC generation (RFC 4226). `AppModel` applies the same validation at
add/replacement/copy boundaries; metadata edits may retain an exact existing secret.
Synthesized Codable decoding intentionally preserves legacy records so one short
key cannot make the whole vault unreadable. `TotpVault` format and AES-256-GCM key
are unchanged. Short-key rows hide countdown/copy controls and explain issuer
re-enrolment; neither padding nor silent key rotation could preserve the issuer's
codes. Existing no-export/no-sync and recovery-custody contracts remain.

Evidence: `TotpTests` covers decoded 15/16-byte boundaries, every supported HMAC
algorithm, RFC 6238 vectors, mutable/decoded bypass attempts and mixed-record JSON
round trips. `TotpVaultTests.mixedLegacyVaultKeepsEveryRecordAndSecret` checks an
encrypted mixed vault; `DemoModeTests.modelRefusesWeakAddsReplacementsAndCopies`
checks the app boundary. Native tests run in `.github/workflows/tests.yml`; the
portable Docker harness exercises TOTP/push source with swift-crypto. These tests
do not establish native TLS peer-key restrictions or physical-device acceptance.


### Native TLS key floor

The unchanged real HTTPClient sent 310 application bytes to a normally trusted
literal RSA-2047 peer on the simulator ([measured run](native-tls-evidence.md)).
Apple’s rounded key block size was therefore not
a sufficient minimum. The session’s TransportPolicy now first requires ordinary
SecTrust SSL/name/time/anchor evaluation, then inspects SecKeyCopyAttributes for
every certificate in the evaluated chain. It accepts RSA>=2048 and prime EC>=256.
It sets no new policies/anchors/trust
exceptions and retains redirect refusal. Strong operator-installed private CAs
remain subject to that same validation and floor. Existing vault/pairing/device
keys and encrypted records are not migrated or discarded.

The two accepted key types are an allowlist, so the check fails closed: an
unreadable key, an absent key size, or any other key type is refused instead of
assumed strong. `nativeKeyAttributesDecideTheChainFloor` proves that per
certificate, driving `TransportPolicy.hasStrongKey` with real fixture
certificates — RSA-2047 and an Ed25519 leaf refused, RSA-2048, P-256, P-384 and
P-521 accepted. Deciding per certificate keeps the floor provable for a key type
the platform may never negotiate.

TLSKeyPolicyTests exercises the real shared transport with loopback peers, no
URLProtocol mock or client trust override. Host calibration checks literal weak
leaf/intermediate/root and directly trusted keys, omitted wire roots, strong
RSA/P-256/P-384/P-521, trust failures and exact TLS versions. Of the twenty
native peers, six must succeed and fourteen must be refused with zero
application bytes; repeated requests and redirect refusal are checked
separately. The full native suite is the runtime verification gate. Go fixture
success alone is not Apple execution, and a successful local/simulator fixture
does not certify a deployment or every supported OS/hardware version.
Test setup/retained results: scripts/tls-fixtures/README.md.

One of those fourteen is a native refusal rather than a policy refusal. The
tested simulator does not negotiate the P-521 peer at all: a delegate-free
ordinary URLSession is refused it too, with `NSURLErrorSecureConnectionFailed`,
while the application policy accepts the same P-521 key and Go calibration
completes an HTTPS round trip against the same fixture. The suite therefore
requires both clients to receive zero HTTP bytes, and the control fails if an
ordinary URLSession ever does negotiate that peer, since the key policy would
then be the only refusal. This is scoped to the simulator, OS build and
certificate configuration measured in
[native TLS evidence](native-tls-evidence.md); it is not a claim that Apple TLS
lacks P-521, and the cause is not isolated to a cipher suite or signature
algorithm.
