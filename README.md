# KyAuth for iOS

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15922/badge)](https://www.bestpractices.dev/projects/15922)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/Busnes-app/KyAuth-iOS/badge)](https://scorecard.dev/viewer/?uri=github.com/Busnes-app/KyAuth-iOS)
[![OctoCounts](https://api.octocounts.com/badge/Busnes-app/KyAuth-iOS/branch/master)](https://octocounts.com/github/Busnes-app/KyAuth-iOS/tree/master)

KyAuth is a native authenticator for iPhone and iPad. Generate local TOTP codes, approve
KyIdentity push MFA requests with number matching, and sign in to supported suite apps
through the KyAuth handoff. It is the iOS counterpart of
[KyAuth for Android](https://github.com/Busnes-app/KyAuth-android).

## What it can do

- Scan or enter TOTP setup keys; codes and secrets stay encrypted on this device.
- Pair an HTTPS KyIdentity server for sign-in requests delivered over Apple Push.
- Approve using Face ID or the device passcode and the browser’s two-digit challenge.
- Sign in to supported Ky apps through an App Group handoff, subject to matching signing/configuration.
- Lock on background/idle, clear copied codes, and use an optional PIN with a five-failure local wipe.

There is no password manager, passkey provider, UnifiedPush, or TOTP backup/export/sync.
Keep each site’s recovery codes elsewhere. Losing the phone or removing its passcode can
make the vault unrecoverable. The demo uses fixed codes and simulated requests; it does
not exercise a server, APNs or a real vault.

## TOTP key requirements and updates

New setup keys need at least **16 decoded bytes** (128 bits); RFC 4226 recommends
20 bytes. Base32 text length alone is not the policy: spaces, case and padding do
not add key material. Obtain a fresh setup key from the account's service when it
is too short; do not pad, hash, repeat or replace an existing issuer's key yourself.

Existing short-key entries stay in the encrypted vault with their names, notes,
issuer and exact secret. They cannot generate or copy codes, and their rows explain
how to set the account up again at its service. You can still edit metadata or
delete an entry. Keep the service's recovery codes and another authorized sign-in
method until the new setup works; deleting the old entry does not re-enrol it.
The update keeps the vault/key format and adds no backup, export or sync.

## Install independently

Requires iOS/iPadOS 17+, a device passcode, and a Mac with Xcode to build from source.
There is no published GitHub application release as of 2026-10-20; App Store/TestFlight
availability is not established by this repository’s build or screenshot scripts.

```sh
git clone https://github.com/Busnes-app/KyAuth-iOS.git
cd KyAuth-iOS
open KyAuth.xcodeproj
```

1. Select the **KyAuth** scheme and an installed iOS simulator to evaluate the UI.
2. For a real iPhone/iPad, select your Apple development team for the app and notification extension and provide matching provisioning, push and App Group/Keychain entitlements. A successful simulator build does not provide these capabilities. The checked-in team identifies the project’s distribution setup, not yours.
3. Build/run on the device. Set its passcode before using the real vault. Add a TOTP account in **Codes** and verify a code at that site; local TOTP does not require KyIdentity.
4. For push MFA, install/configure [KyIdentity](https://github.com/Busnes-app/KyIdentity-server), including its APNs relay, app identity/attestation settings and certificate configuration. Create a pairing QR in KyIdentity’s device settings, scan it or enter its URL/token, and confirm before the 90-second token expires.
5. Allow notifications, initiate a real browser sign-in, and approve the matching challenge. Verify delivery on a locked/backgrounded physical device separately. Pairing waits for a real APNs token.

Preserve the signing identity and access groups when updating a paired install. Uninstall,
erase and re-pairing are not data-preserving upgrade methods. KyIdentity account recovery
uses its recovery codes or administrator reset, independently of local TOTP entries.

## Build and verification

Use an installed simulator destination (list them with `xcodebuild -showdestinations` for
the project/scheme):

```sh
bash scripts/test-ios.sh DISPOSABLE_SIMULATOR_UUID
```

The full suite also needs Go 1.26.10 and the reserved host mapping
`127.0.0.1 kyauth-tls-test.invalid`. Use a disposable simulator: the runner imports
an ephemeral fixture root there and starts HTTPS peers on host loopback only.
[Native TLS fixture instructions](scripts/tls-fixtures/README.md) explain the
key-floor regressions, generated files and controls. The app retains native
certificate trust and additionally checks actual RSA/EC bits across the evaluated
chain; see [server certificate requirements](SECURITY.md#operating-requirements).

Simulator tests do not verify APNs delivery, Secure Enclave signing, App Attest, Face ID
prompts, camera scanning, the notification extension’s shared Keychain group, or KyPost’s
real sign-on round trip. Those require physical-device acceptance. CI
(`.github/workflows/tests.yml`) runs the complete simulator suite; the separate
CodeQL workflow builds and scans the app and notification extension. Swift warnings
are configured as build errors in Debug and Release, including CodeQL. CI is
configured to build Release and retain validated app line counts in `coverage.json`
after successful tests and evidence export. These additions await native CI evidence.
Absent or unexercised extension coverage is reported separately. Line counts do
not establish branch, input or requirement coverage. Recorded hardware
observations and exact build contracts are in [KyAuth/AGENTS.md](KyAuth/AGENTS.md).

Without Xcode, `scripts/check-push-crypto-linux.sh` runs push cryptographic vectors
and portable TOTP import/generation/legacy-record tests in Docker against swift-crypto. It does not verify Apple CryptoKit, the encrypted
vault/Keychain integration or SwiftUI. `scripts/capture-screenshots.sh` uses demo
fixtures and is a capture workflow,
not evidence of live push or security qualification. Design contracts are in `docs/specs/`.

## Security and contributing

- Report vulnerabilities privately through the repository's **Security** tab
  ([policy](https://github.com/Busnes-app/.github/blob/main/SECURITY.md)).
- [Contributing](CONTRIBUTING.md) — process, tests and coding standard.
- [Verifying releases](docs/VERIFYING-RELEASES.md) — what you can check of an App Store build, and what you cannot.
- [Assurance case](docs/ASSURANCE-CASE.md) — threat model, trust boundaries, and why the security requirements are met.

## License

[MIT](LICENSE.txt).
