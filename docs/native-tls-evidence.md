# Native TLS key-floor evidence

[Assurance case](ASSURANCE-CASE.md) · [Security policy](../SECURITY.md) · [Fixture setup](../scripts/tls-fixtures/README.md)

Observations behind the all-chain certificate-key floor in
`KyAuth/Networking/HTTPClient.swift`. CI artifacts expire, so the measurements
that an assurance answer depends on are recorded here with their source runs.
Each row is a counter from the fixture server the run actually talked to:
`bytes` are plaintext application bytes after TLS, `requests` are HTTP requests
the peer served, `connections` are accepted TCP connections.

These runs are `iOS simulator tests` on `Busnes-app/KyAuth-iOS`, on a
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

## 4. The repaired native assertions pass

[Run 40434935123](https://github.com/Busnes-app/KyAuth-iOS/actions/runs/40434935123),
commit `c24c899`, success: 89 passed, 1 skipped, 0 failed. The device summary
confirms iPhone 17 Pro, iOS 26.4.1 (23E254a), arm64 simulator.

`ordinaryNativeStrongCurveControls` and
`nativeKeyAttributesDecideTheChainFloor` both pass. The direct certificate test
accepts RSA-2048, P-256, P-384 and P-521 and refuses RSA-2047 and Ed25519,
separately from TLS negotiation. Thus the measurable P-521 key meets the
application floor even though this fixture's native handshake is refused.

| Peer | bytes | requests | connections |
| --- | --- | --- | --- |
| `p256` | 550 | 2 | 2 |
| `p384` | 550 | 2 | 2 |
| `p521` | 0 | 0 | 2 |
| `rsa2048` | 620 | 2 | 1 |
| `tls12` | 310 | 1 | 1 |
| `tls13` | 310 | 1 | 1 |

Every weak RSA leaf, intermediate, root and direct-trust peer, plus expired,
wrong-host, untrusted and TLS 1.0/1.1 peers, records 0 bytes and 0 requests.
The current suite therefore confirms the reclassification without dropping the
P-521 fixture, bypassing native trust or weakening the key floor. Platform scope
remains the simulator, OS build and certificate configuration described above.

## What these runs do not establish

- No live deployment, physical device, or OS/hardware version other than the one
  named above is certified by a simulator run.
- Go fixture calibration proves the fixtures are usable, never iOS behavior.
- The weak and TLS 1.0/1.1 fixtures run with Go FIPS mode off. That is fixture
  setup; it changes no application policy or production dependency.
