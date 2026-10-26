# Security Policy

KyAuth is an authenticator client for KyIdentity on iOS. It holds TOTP seeds, passkey credentials, and push-approval keys locally and approves sign-ins on an explicit user action.

## Reporting vulnerabilities

Report security vulnerabilities privately through GitHub Security Advisories:
<https://github.com/Busnes-app/KyAuth-iOS/security/advisories/new>. Do not open a public issue.
Include the affected area, reproduction steps, impact, and affected versions.
We aim to acknowledge reports within two business days and will coordinate a fix
and disclosure.

## Trust boundaries and limitations

- Authenticator secrets live on the device, protected by the iOS Keychain and Secure Enclave. The app must not upload them or write them to logs or crash reports.
- A push or MFA approval is a deliberate user action. The app must not auto-approve, and a notification alone is not consent.
- The device is the trust boundary: anyone with the unlocked device can use the codes. Gate secrets behind biometrics / passcode where available.

## Operating requirements

- Fetch sign-in requests over HTTPS from the configured KyIdentity only; refuse redirects to other hosts.
- Do not weaken the Keychain protection class or add an insecure transport exception to quiet a first run.

## Security-sensitive changes

Changes to Keychain/Secure Enclave storage, enrollment, push-approval handling, passkey flows, or logging require tests for both the expected path and the relevant
failure or attack path, plus a description of the trust boundary in the pull
request.

## Related documents

- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution and review requirements
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — community expectations
- [README.md](README.md) — what this project is and how to run it

