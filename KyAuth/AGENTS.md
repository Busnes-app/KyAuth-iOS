# KyAuth iOS app

## Purpose

KyAuth for iPhone and iPad: the KyIdentity authenticator (TOTP, Push MFA, KyIdentity sign-on for
suite apps). A port of `Busnes-app/KyAuth-android` with native iOS UI. iOS 17+, iPhone and iPad
only: no macOS, Mac Catalyst, visionOS or tvOS.

## Ownership

- `App/`: `KyAuthApp` (scene phase, URL handling), `AppDelegate` (APNs, notifications), `AppModel`
  (all state and workflows; views only call it), `DemoMode` (App Store review demo data).
- `Pairing/`: QR/link parsing, endpoint validation, `PairingClient`, `PairingStore`,
  `DeviceSigningKey` (Secure Enclave), `AppAttestor` + `AttestationReason`, `PushStore`,
  `PushRefreshClient`.
- `Mfa/`: push parsing, the signed response message, the pending-request store, `MfaResponseClient`.
- `SignOn/`: `DeviceAssertion`, `TokenClient`, `SignOnHandoff` + `TrustedConsumers`.
- `Totp/`: entries, generator, `otpauth://` parsing, `TotpVault`.
- `Security/`: `UserPresence`, PIN policy and store, `IdleLock`, `LocalWipe`.
- `../Shared/` (compiled into the app and the extension): `Keychain` + `KeychainCodable`, `PushKeyStore`,
  `PushCrypto` (`PushKeys`, RFC 8291 `WebPush.decrypt`, `PushPayload`).
- `../KyAuthPush/`: the notification service extension (`org.kysecurity.authenticator.push`).
- `UI/`: SwiftUI screens.
- `PrivacyInfo.xcprivacy`: the App Store privacy manifest.

## Local Contracts

- Wire contracts with KyIdentity are byte-exact and covered by golden-vector tests:
  `kyidentity-push-v2` (MFA answers), `kyidentity-push-token-v2` with transport `fcm` (the relay
  transport, which also carries APNs; KyIdentity master since PR #87), RFC 7523 device assertions (raw
  `r||s`). Registration always sends `platform: "ios"`; an omitted platform is stored as Android.
- Sealed pushes: every pairing makes a software P-256 key and 16-byte auth secret (`PushKeys`), stored
  before registration as one `AfterFirstUnlockThisDeviceOnly` item in access group
  `group.org.kysecurity.authenticator.push` (the only group the extension holds), and sends them as
  `pushP256dh`/`pushAuth` (base64url, no padding). KyIdentity then sends only `type` and `kyauth`, the
  RFC 8291 `aes128gcm` body of the challenge JSON. A refresh re-sends the keys: one without them clears
  them on the server. A pairing with keys refuses plaintext pushes; only a pairing made before keys
  existed reads plaintext. Unpair, re-pair and erase delete the keys. Vectors: `PushCryptoTests`.
- The extension rebuilds every alert from fixed text ("Sign-in request" or "Confirm a sensitive action",
  "Open KyAuth to review."), never payload text or the username. It opens the payload only to choose
  the title; the app opens it again in `handlePush`, so nothing the extension writes is trusted.
- App Attest grading: `docs/specs/2026-10-11-ios-app-attest.md`. Sign-on handoff:
  `docs/specs/2026-10-11-ios-signon-handoff.md`. Change either only together with its counterpart
  (KyIdentity-server, KyPost-for-Mac).
- Release builds require HTTPS; debug builds also accept loopback HTTP.
- `PrivacyInfo.xcprivacy` declares every required-reason API the app uses (now `UserDefaults`
  CA92.1, `systemUptime` 35F9.1, file timestamps C617.1) and no tracking. Collected data: Device ID
  and User ID, app functionality, linked to the user (they are part of signing in), because the
  developer-run APNs relay receives the push token (and keeps its hash) and, for a pairing without
  push keys only, KyIdentity's IDs in plaintext; sealed pushes carry none. Adding a use from another category, or for another reason,
  updates it in the same change, together with `Distribution/AppStore/app-privacy.md`.
- Device key: Secure Enclave P-256, `.privateKeyUsage` + `.userPresence`, replaced at every pairing
  (a failed re-pair leaves the phone unpaired). A software key exists only in the simulator.
- Every signature and every vault unlock takes exactly one Face ID / passcode check; the evaluated
  `LAContext` is passed to the Keychain or key and invalidated after use. Push MFA and sign-on never
  touch the vault key, so they work while locked.
- TOTP vault: AES-256-GCM file excluded from backup, key in a `.userPresence`,
  `WhenPasscodeSetThisDeviceOnly` Keychain item. No backup, export or sync, by decision. A device
  without a passcode cannot use KyAuth.
- New/imported/replaced TOTP keys require 16 decoded bytes (RFC 4226). Generation checks
  the same floor, including Codable-restored or mutable entries. Keep legacy vault records and
  their exact secrets readable/editable/deletable; metadata edits may retain an unchanged
  secret. Never pad, replace or drop one silently. Short-key rows explain issuer re-enrolment,
  hide countdowns and refuse copy/generation. No export or sync is added.
- Keychain items are this-device-only and never synced; a fresh install erases leftovers.
- Only an absent vault file loads as empty; an empty or unreadable file is an error and saving
  stays disabled, so a write can never replace entries that failed to load.
- A vault file whose key is gone (the passcode was removed) is never given a new key: it unlocks
  with no codes, saving disabled and the reason shown, so Erase All Data stays reachable.
- The Codes tab scanner (`ScannedCode`) adds `otpauth://` accounts and hands a KyIdentity pairing
  code to `PairingView(scanned:)`, which pairs only after a tap (pairing replaces the device key).
- The pairing form's contents (`AppModel.pairingDraft`, memory only) survive a lock, and the form
  reopens after unlock: pairing by link or by hand means leaving KyAuth. Pairing waits up to 15 s
  for an APNs token and fails with Apple Push's reason when it refuses.
- `otpauth://` defaults apply only to omitted parameters; an unsupported algorithm or a malformed
  or valueless `digits`/`period`/`algorithm` is refused.
- Secrets are typed only into secure fields (setup key, PINs), and third-party keyboards are
  refused app-wide.
- One sign-on at a time: a request arriving during another is answered with a busy error, and
  KyAuth does not switch to its consumer while a sign-in is on screen. A sign-on answer that cannot
  be written is kept in memory and retried (on activation and on the next sign-on link) until the
  consumer's 180 s wait ends; the request file is already consumed, so the answer is never dropped.
- Locking: immediate on background; foreground idle lock 1/5/15/30/60 minutes (default 5) on system
  uptime. Locking clears codes, the key and a copied code; the app switcher and screen capture show
  a cover. Copied codes are local-only and expire at the end of their period.
- Optional PIN after Face ID: delays 0/5/30/300 s on system uptime (a restart restarts the delay,
  never shortens it), the fifth failure erases all local data. A PIN whose verifier is gone with
  the passcode is turned off at unlock, not counted as failures.
- Push MFA: a push must name this device and account, carry `purpose` and an expiry at most 10
  minutes ahead; a payload `serverUrl` is ignored. KyIdentity's push names no user, so the card
  shows the paired account's username. Approve needs the two digits typed from the
  browser: the phone never holds the answer, so match or decoy numbers in a payload are dropped
  and no choice of numbers is ever offered. A 2xx answer without a decision is an error.
- Demo mode ("Try Demo" on the lock screen, or "Explore the Demo" on an empty Codes tab; unpaired
  phones only) is for App Store review: fixed
  codes and a simulated request every 15 s with `.invalid` server, held in memory. With no browser,
  the card names the number to type as demo text, kept in `AppModel` and never in the request. It needs no Face
  ID, reads and writes no vault, Keychain, pairing or network; Settings hides PIN, auto-lock, pairing
  and erase. Any lock (background, idle, Lock, Exit Demo) ends it.
- The lock screen prompts for Face ID on its own only when paired or a vault file exists; a fresh
  install waits for a tap, so Try Demo is reachable without a passcode prompt.
- `docs/ASSURANCE-CASE.md` argues that these contracts meet KyAuth's security requirements, with
  file paths as evidence. A change that moves a trust boundary or a cited path updates it in the
  same change. `docs/VERIFYING-RELEASES.md` says what a user can and cannot check of a store build.
- No Android features without an iOS counterpart: no UnifiedPush, no credential provider/passkeys
  (dropped by decision), no `AccountManager` (replaced by the handoff).

## Work Guidance

- Native iOS look: system `TabView` (Codes, Settings), forms and lists, Busnes palettes: background
  `BusnesBackground` (`#f8f6f0` / `#182326`), rows and cards `BusnesSurface` (`#ffffff` /
  `#1f2b2e`), orange accent (`#bf3f18` / `#f5865f`); text keeps system label colors. Use
  `BusnesForm`/`BusnesList` instead of `Form`/`List`, `Color.busnesBackground` behind other
  screens, and `busnesProminentButton()` for filled buttons (`BusnesOnAccent` label: white /
  `#182326`, since white fails contrast on the dark accent).
- Appearance setting: System (default, follows iOS), Busnes Light, Busnes Dark, set on the window
  (`UI/Appearance.swift`). No other themes: Android's other 15 themes are not ported, by decision.
- No third-party dependencies. Keep security checks fail-closed and add a focused test for
  non-trivial logic.

## Verification

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project KyAuth.xcodeproj \
  -scheme KyAuth -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO test
```

Not verifiable in the simulator: APNs delivery, Secure Enclave signing, App Attest, Face ID prompts,
the camera scanner, the sign-on round trip with KyPost, the notification service extension and its
shared Keychain group. Installed on an iPhone, and plaintext APNs delivery through the real relay
observed there (2026-10-13); encrypted pushes and the extension are not yet observed on hardware.

CI (`.github/workflows/tests.yml`) runs the complete simulator test suite on Xcode 26.
Without Xcode, `scripts/check-push-crypto-linux.sh` (Docker) runs `PushCryptoTests` and
`TotpTests` against swift-crypto with a persistent SwiftPM dependency cache. It does not
verify Apple CryptoKit, vault/Keychain integration or SwiftUI. The encrypted mixed-legacy
vault and model-boundary tests require the simulator.

App Store screenshots: `scripts/capture-screenshots.sh [iphone|ipad|duo|all]` drives the demo
through `KyAuthUITests/ScreenshotTests` (skipped unless `KYAUTH_SCREENSHOTS=1`) into
`Distribution/Screenshots/` (iPhone 6.3", iPad 13", iPhone Duo outer and inner; light and dark).
The Duo needs the iOS 27.1 simulator runtime and boots folded; its inner display is captured only
after unfolding it by hand in DeviceHub. `swift scripts/render-header.swift` then draws the App Store
product page header (3840 x 1646) and search artwork (3840 x 2560) into `Distribution/Promo/` from
those screenshots. Listing text, one file per App Store Connect field, is in
`Distribution/AppStore/en-US/` (including the privacy policy and support URLs); keep its claims true
to the app. App Review notes are `Distribution/AppStore/review_notes.txt`, the App Privacy answers
`Distribution/AppStore/app-privacy.md`.

## Child DOX Index

No child `AGENTS.md` files exist.
