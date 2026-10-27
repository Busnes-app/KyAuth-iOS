# Native TLS key-floor evidence

[Assurance case](ASSURANCE-CASE.md) · [Security policy](../SECURITY.md) · [Fixture setup](../scripts/tls-fixtures/README.md)

Observations behind the all-chain certificate-key floor in
`KyAuth/Networking/HTTPClient.swift`. CI artifacts expire, so the measurements
that an assurance answer depends on are recorded here with their source runs.
Each row is a counter from the fixture server the run actually talked to:
`bytes` are plaintext application bytes after TLS, `requests` are HTTP requests
the peer served, `connections` are accepted TCP connections.

All three runs are `iOS simulator tests` on `Busnes-app/KyAuth-iOS`, on a
GitHub-hosted ephemeral macOS runner: iPhone 17 Pro simulator, iOS 26.4.1
(build 23E254a), arm64, built with macOS 26.6.2, Xcode 26, Go 1.26.10.

## 1. The unchanged client accepted a literal RSA-2047 peer

[Run 40414013888](https://github.com/Busnes-app/KyAuth-iOS/actions/runs/40414013888),
commit `9c1ed70`, success. The production `HTTPClient` with no key floor, against
normally trusted loopback peers:

| Peer | bytes | requests | connections |
| --- | --- | --- | --- |
| `rsa2047` | 310 | 1 | 1 |
| `rsa2048` | 620 | 2 | 1 |
| `p256` | 310 | 1 | 1 |

Ordinary `SecTrust` evaluation therefore did not impose a literal RSA-2048
minimum: a 2047-bit peer received application bytes. RSA-2047 and RSA-2048 share
a 256-byte block size, so the rounded block size cannot implement the floor.
This is the defect the key floor fixes, and a green suite at this commit was not
a repair.

## 2. With the floor: every weak and invalid peer refused, P-521 also refused

[Run 40417055180](https://github.com/Busnes-app/KyAuth-iOS/actions/runs/40417055180),
commit `1a82e2a`, failure. Twenty peers. Weak RSA at leaf, intermediate, root and
direct-trust positions, expired, wrong-host and untrusted peers, and TLS 1.0/1.1
each received 0 bytes and 0 requests on 1 connection. `rsa2048` 620/2,
`trusted2048` 310/1, `tls12` 310/1, `tls13` 310/1, `p256` 310/1, `p384` 310/1.

`p521` received 0 bytes and 0 requests on 1 connection: refused before HTTP. At
this commit the refusing layer was not identified.

## 3. P-521 is refused by the platform, not by the application policy

[Run 40427678337](https://github.com/Busnes-app/KyAuth-iOS/actions/runs/40427678337),
commit `4a7e133`, failure. This run added a control that drives the same peers
through an ordinary `URLSession(configuration: .ephemeral)` with no delegate, no
trust override and no application key policy:

| Peer | bytes | requests | connections | ordinary URLSession |
| --- | --- | --- | --- | --- |
| `p256` | 550 | 2 | 2 | 200 |
| `p384` | 550 | 2 | 2 | 200 |
| `p521` | 0 | 0 | 2 | refused, `NSURLErrorDomain` code `-1200` |

Both connections to `p521` — one from the production client, one from the
delegate-free client — completed TCP and obtained no HTTP. Code `-1200` is
`NSURLErrorSecureConnectionFailed`: the handshake, not the application.

The same P-521 fixture is serviceable: `TestFixtureCalibrationAndConnectionReuse`
confirms the leaf carries a genuine 521-bit ECDSA key and a Go client completes
the HTTPS round trip against it with connection reuse. That part is host
calibration, verified locally, and says nothing about iOS.

**Scope.** This establishes that *on this simulator and OS build, for this
fixture's negotiated parameters*, Apple's TLS client refuses this P-521 peer
before any HTTP, with and without the app's delegate. It does **not** establish
that Apple TLS lacks P-521 support generally. The refusal is not root-caused to a
specific cipher suite or certificate signature algorithm; only the refusal is
observed. Other OS versions, physical devices, and other P-521 certificate or
chain configurations are untested.

`p521` is therefore classified as a native refusal: the fixture, the host
positive calibration and the per-certificate policy check are all retained, and
the suite asserts the negative that both clients receive zero HTTP bytes and zero
requests. No strong control is skipped, and no refusal is excused: if an ordinary
URLSession ever does negotiate this peer, the control fails, because the key
policy would then be the only thing refusing it.

## Asserted, not yet observed

The reclassification above is written into the suite but has not run on a hosted
runner yet. These expectations are unproven until a run at or after the commit
that added them reports them, and this section must be replaced with its run
link and counters once it does:

- `p521` is required to be refused with zero HTTP bytes and zero requests by
  both the production client and the delegate-free control, which is what runs 2
  and 3 measured.
- `nativeKeyAttributesDecideTheChainFloor` drives `TransportPolicy.hasStrongKey`
  on fixture leaves and requires RSA-2048, P-256, P-384 and P-521 accepted,
  RSA-2047 and Ed25519 refused. P-521 accepted here is the assertion that places
  the refusal in the handshake rather than in the application; if Security
  .framework does not report a measurable 521-bit EC key, that is a finding
  about this conclusion and not a reason to relax the floor.

Locally verified instead, without an Apple SDK: the Ed25519 and P-521 fixture
certificates are generated, served by `/certificate/`, and parse as an Ed25519
leaf and a 521-bit EC leaf for the host `kyauth-tls-test.invalid`.

## What these runs do not establish

- No live deployment, physical device, or OS/hardware version other than the one
  named above is certified by a simulator run.
- Go fixture calibration proves the fixtures are usable, never iOS behavior.
- The weak and TLS 1.0/1.1 fixtures run with Go FIPS mode off. That is fixture
  setup; it changes no application policy or production dependency.
