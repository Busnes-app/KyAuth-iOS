# Verifying releases

[Product overview](../README.md) · [Assurance case](ASSURANCE-CASE.md)

> **Untested.** KyAuth for iOS was approved by App Review but was not yet on sale on
> 2026-10-23, when this page was written. Nothing here has been run against a store install.

KyAuth for iOS ships **only through Apple's App Store** (and TestFlight before that). There
are no GitHub releases, no downloadable `.ipa` files and no project-held signing key. This
page says what a user can check, and what this project cannot offer.

## What is signed, and by whom

- The app is `org.kysecurity.authenticator`, with its notification extension
  `org.kysecurity.authenticator.push`, built by Apple developer team `TATYN4X57D`
  (`KyAuth.xcodeproj/project.pbxproj`).
- Apple re-signs every App Store and TestFlight build with its own certificate. iOS checks
  that signature when it installs the app and every time it launches it, and refuses an
  app that was changed after signing. **That check is your verification, and iOS runs it for
  you.** You cannot run it by hand on an iPhone, and the project has no key you could check
  it against.
- Install KyAuth only from its App Store listing. A build from anywhere else, such as a
  web download or a configuration profile, is not a KyAuth release.

## What KyIdentity checks for you

When you pair, KyAuth asks Apple's App Attest service to vouch for the pairing request. A
KyIdentity server that lists `TATYN4X57D.org.kysecurity.authenticator` in
`KYIDENTITY_APPATTEST_APP_IDS` then grades the device `appattest` only if Apple confirms
that a genuine copy of this App ID made the request
([docs/specs/2026-10-11-ios-app-attest.md](specs/2026-10-11-ios-app-attest.md)). KyAuth's
Settings shows the result ("Verified by App Attest"). So your administrator can tell a
store-signed KyAuth from a modified or self-built one.

## Which source a store build came from

Each store build is a `release: <version> build <n>` commit on `master` that sets
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. The version appears in KyAuth's Settings
(for example `v0.5.0`). To find the commit that set a build number:

```bash
git clone https://github.com/Busnes-app/KyAuth-iOS.git && cd KyAuth-iOS
git log --format='%h %s' -G 'CURRENT_PROJECT_VERSION = 2;' -- KyAuth.xcodeproj/project.pbxproj
```

For 0.5.0 build 2 this prints `4f7c085 release: 0.5.0 build 2`. This is a record, not
proof: nothing ties the binary Apple distributes to that commit. Release commits are not
tagged yet.

## What this project cannot offer

- **A signature you can check yourself.** App Store apps are signed by Apple, not by the
  project, and the project publishes no key of its own.
- **A byte-for-byte comparison with a source build.** Apple encrypts each App Store binary
  with FairPlay and re-signs it, so the installed bytes never match a build from source.
  Whether two Xcode builds of the same commit give the same bytes has not been tested
  (there is no Xcode on the machine this page was written on).
- **A software bill of materials.** There is little to list: the app has no third-party
  packages and uses only Apple frameworks.

## If you would rather trust your own build

Build KyAuth from source with your own Apple developer team ([README](../README.md#install-independently)).
Push sign-in then needs your own APNs setup, and App Attest grading needs your App ID added to
`KYIDENTITY_APPATTEST_APP_IDS` on your KyIdentity server. Local TOTP needs neither.
