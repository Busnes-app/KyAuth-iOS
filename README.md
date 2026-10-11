# KyAuth for iOS

KyAuth is the KyIdentity authenticator for iPhone and iPad: TOTP codes, Push MFA sign-in
requests over Apple Push, and KyIdentity sign-in for suite apps such as KyPost. It is the iOS
counterpart of [KyAuth for Android](https://github.com/Busnes-app/KyAuth-android).

- Codes stay on the phone, encrypted, with no backup or sync.
- The device key lives in the Secure Enclave; every approval takes Face ID or the passcode.
- iOS 17 or later. A device passcode is required.

Build and test: see `KyAuth/AGENTS.md` (Verification). Design contracts are in `docs/specs/`.

MIT License, see `LICENSE.txt`.
