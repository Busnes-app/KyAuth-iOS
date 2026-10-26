# KyAuth for iOS

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15922/badge)](https://www.bestpractices.dev/projects/15922)

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
xcodebuild -project KyAuth.xcodeproj -scheme KyAuth \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

Simulator tests do not verify APNs delivery, Secure Enclave signing, App Attest, Face ID
prompts, camera scanning, the notification extension’s shared Keychain group, or KyPost’s
real sign-on round trip. Those require physical-device acceptance. CI (`.github/workflows/codeql.yml`)
builds the app for the simulator and runs CodeQL on it; it does not run the tests. Recorded hardware
observations and exact build contracts are in [KyAuth/AGENTS.md](KyAuth/AGENTS.md).

Without Xcode, `scripts/check-push-crypto-linux.sh` runs only the push cryptographic vectors
in Docker. `scripts/capture-screenshots.sh` uses demo fixtures and is a capture workflow,
not evidence of live push or security qualification. Design contracts are in `docs/specs/`.

## Security and contributing

- Report vulnerabilities privately through the repository's **Security** tab
  ([policy](https://github.com/Busnes-app/.github/blob/main/SECURITY.md)).
- [Contributing](CONTRIBUTING.md) — process, tests and coding standard.
- [Verifying releases](docs/VERIFYING-RELEASES.md) — what you can check of an App Store build, and what you cannot.
- [Assurance case](docs/ASSURANCE-CASE.md) — threat model, trust boundaries, and why the security requirements are met.

## License

[MIT](LICENSE.txt).
