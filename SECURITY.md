# Security Policy

KyAuth is an authenticator client for KyIdentity on iOS. It holds TOTP seeds and push-approval keys locally and approves sign-ins on an explicit user action.

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
- Keep native certificate name, validity and trust validation. Every certificate in
  the evaluated chain, including its anchor, must have an actual RSA key of at
  least 2048 bits or prime-curve EC key of at least 256 bits. No trust bypass or
  weak-key opt-out is provided.
- Those two key types are an allowlist, and the check fails closed: a key the app
  cannot read, a certificate reporting no key size, or any other key type —
  Ed25519 included — is refused rather than assumed strong. Issue KyIdentity
  server certificates with RSA or a NIST prime curve.
- Meeting the floor does not make a certificate negotiable: iOS can refuse a
  strong one during the handshake, before the app sees it. On the tested
  simulator a P-521 peer was refused that way, by an ordinary URLSession as well
  as by KyAuth ([evidence](docs/native-tls-evidence.md)). Prefer P-256 or P-384,
  and verify a new chain against the app rather than against the floor alone.
- If an existing server uses an undersized certificate or CA, retain working
  administrator access and arrange a verified strong certificate/chain before
  upgrading it. Preserve pairing, device keys and vault data; resetting them
  cannot repair server TLS. Strong private CAs installed through iOS remain
  subject to normal trust and the same floor.
- Do not weaken the Keychain protection class or add an insecure transport exception to quiet a first run.

## Security-sensitive changes

Changes to Keychain/Secure Enclave storage, enrollment, push-approval handling, TLS trust, or logging require tests for both the expected path and the relevant
failure or attack path, plus a description of the trust boundary in the pull
request.

## Related documents

- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution and review requirements
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — community expectations
- [README.md](README.md) — what this project is and how to run it

