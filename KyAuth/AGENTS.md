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
- `Security/`: Keychain, `UserPresence`, PIN policy and store, `IdleLock`, `LocalWipe`.
- `UI/`: SwiftUI screens.
- `PrivacyInfo.xcprivacy`: the App Store privacy manifest.

## Local Contracts

- Wire contracts with KyIdentity are byte-exact and covered by golden-vector tests:
  `kyidentity-push-v2` (MFA answers), `kyidentity-push-token-v2` with transport `fcm` (the relay
  transport, which also carries APNs; KyIdentity master since PR #87), RFC 7523 device assertions (raw
  `r||s`). Registration always sends `platform: "ios"`; an omitted platform is stored as Android.
- App Attest grading: `docs/specs/2026-10-11-ios-app-attest.md`. Sign-on handoff:
  `docs/specs/2026-10-11-ios-signon-handoff.md`. Change either only together with its counterpart
  (KyIdentity-server, KyPost-for-Mac).
- Release builds require HTTPS; debug builds also accept loopback HTTP.
- `PrivacyInfo.xcprivacy` declares every required-reason API the app uses (now `UserDefaults`
  CA92.1, `systemUptime` 35F9.1, file timestamps C617.1), no tracking and no collected data.
  Adding a use from another category, or for another reason, updates it in the same change.
- Device key: Secure Enclave P-256, `.privateKeyUsage` + `.userPresence`, replaced at every pairing
  (a failed re-pair leaves the phone unpaired). A software key exists only in the simulator.
- Every signature and every vault unlock takes exactly one Face ID / passcode check; the evaluated
  `LAContext` is passed to the Keychain or key and invalidated after use. Push MFA and sign-on never
  touch the vault key, so they work while locked.
- TOTP vault: AES-256-GCM file excluded from backup, key in a `.userPresence`,
  `WhenPasscodeSetThisDeviceOnly` Keychain item. No backup, export or sync, by decision. A device
  without a passcode cannot use KyAuth.
- Keychain items are this-device-only and never synced; a fresh install erases leftovers.
- Only an absent vault file loads as empty; an empty or unreadable file is an error and saving
  stays disabled, so a write can never replace entries that failed to load.
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
- Optional PIN after Face ID: delays 0/5/30/300 s, the fifth failure erases all local data.
- Push MFA: a push must name this device and account, carry `purpose` and an expiry at most 10
  minutes ahead; a payload `serverUrl` is ignored. Approve needs the two digits from the browser.
  A 2xx answer without a decision is an error.
- Demo mode ("Try Demo" on the lock screen, unpaired phones only) is for App Store review: fixed
  codes and a simulated request every 15 s with `.invalid` server, held in memory. It needs no Face
  ID, reads and writes no vault, Keychain, pairing or network; Settings hides PIN, auto-lock, pairing
  and erase. Any lock (background, idle, Lock, Exit Demo) ends it.
- The lock screen prompts for Face ID on its own only when paired or a vault file exists; a fresh
  install waits for a tap, so Try Demo is reachable without a passcode prompt.
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
  -scheme KyAuth -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

Not verifiable in the simulator, and not yet observed on hardware: APNs delivery, Secure Enclave
signing, App Attest, Face ID prompts, the camera scanner, the sign-on round trip with KyPost.

## Child DOX Index

No child `AGENTS.md` files exist.
