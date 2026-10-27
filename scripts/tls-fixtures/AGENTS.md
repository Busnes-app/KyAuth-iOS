# Native TLS fixtures

## Purpose

Qualify the actual KyAuth iOS HTTPClient against controlled HTTPS peers on an
owned simulator. This is test infrastructure, separate from the application.

## Ownership

Own the standard-library Go fixture server, certificate generator and public
test keys. Root owns CI and the simulator runner; KyAuth owns production TLS.

## Local Contracts

- Listen only on loopback. Never log request headers or bodies.
- Certificate/key files are deliberately public test material. Never use real
  credentials or a production certificate authority; the generated CA private
  key is discarded instead of being stored.
- The server permits undersized fixture keys to test client refusal. This
  changes no application trust or TLS setting.
- Calibrate weak leaf/intermediate/root and directly trusted peers as usable
  fixtures, plus strong RSA/EC, trust failures and exact TLS versions. Native
  refusal must receive zero application bytes; Go calibration is separate.
- `certificateOnlyNames` is material served by `/certificate/` for key-policy
  inspection: a real certificate with no listener and no private key, so the
  client's decision on a key type the platform may never negotiate stays
  testable. Keep it out of `fixtureNames` and out of the native peer matrix.
- Import only generated fixture anchors into an explicitly selected disposable
  simulator. Never import the untrusted control root.

## Work Guidance

- Use Go's standard crypto/x509 and TLS implementations; add no dependencies.
- Keep exact modulus sizes, hostname validity and strong controls checked.
- Track plaintext application bytes after TLS, including unsuccessful requests.
- A fixture the platform refuses to negotiate keeps its peer and its host
  calibration; the native suite reclassifies the case and asserts the refusal.
  Never delete a fixture to make a native suite green.

## Verification

`go test -race -count=1 ./...` verifies fixture strength, counters and keepalive.
The root simulator workflow qualifies native HTTPClient behavior separately.

## Child DOX Index

None.
