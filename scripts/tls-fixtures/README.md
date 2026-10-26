# Native TLS fixture baseline

These peers measure the unchanged app HTTPClient on an iOS simulator. They do
not establish a passing cryptographic policy. The app's normal trust, ATS,
cookie/cache settings and redirect refusal remain in effect; no URLProtocol
mock or client trust override is used.

The standard-library Go server generates an RSA-3072 root and short-lived
RSA-2048, literal RSA-2047 and P-256 peer certificates. The CA private key is
discarded. Generated keys/results are ignored under `.tls-fixtures/`, outside
the app and test bundles. Certificates contain only the reserved fixture name.

## Native run

Use Xcode 26, Go 1.26.10 and a disposable iOS simulator. Obtain its UUID with
`xcrun simctl list devices available`. Add this mapping to the Mac's hosts file:

```text
127.0.0.1 kyauth-tls-test.invalid
```

Then, from the repository root:

```sh
GODEBUG=fips140=off go -C scripts/tls-fixtures test -race -count=1 ./...
bash scripts/test-ios.sh DISPOSABLE_SIMULATOR_UUID
```

The runner checks the mapping, boots the selected simulator, imports only the
fixture root into that simulator, starts four loopback-only listeners on ports
46100–46103 and runs the complete scheme. It never edits a local hosts file or
touches a physical device. Erase the disposable simulator when done to remove
its test root. CI performs this setup only on its ephemeral macOS runner.

Results are retained in `.tls-fixtures/results-*/TestResults.xcresult`, with
public post-suite counters alongside it in `fixture-stats.json` and the console.
Fixture startup output is in `.tls-fixtures/server.log`. CI explicitly includes
hidden paths when uploading only the results directories; generated certificate
keys are outside that upload. No request body/header or real credentials are
logged. The fixture server is stopped when the runner exits; a failed test run
still captures counters and retains its failing exit status.

## Reading the measurements

- Strong RSA and EC controls must succeed. The key-attribute test requires
  Security.framework to report literal 2047 bits rather than a rounded block size.
- `KYAUTH_TLS_BASELINE` records actual app acceptance/refusal and plaintext HTTP
  bytes received after TLS. A refused connection must receive zero app bytes.
- `KYAUTH_TLS_REUSE` records two successful requests and actual connection count.
  Pooling is claimed only when the observed connection count establishes it.
- The redirect test requires 302 to reach the caller without sending bytes to
  the target peer.

The RSA-2047 outcome is deliberately recorded rather than prescribed during
baseline collection. If accepted, a later app change must add and verify the
missing floor; if refused, preserve and qualify the platform enforcement. Do not
turn baseline success into a compliant whole-product answer. Weak roots,
intermediates, directly trusted peers, TLS versions and further negative controls
remain separate qualification cases after this first native observation.

## Host calibration

The Go tests verify exact key sizes, certificate/hostname trust, repeated HTTP
requests on one connection, and zero application bytes after failed trust. This
proves fixtures work; it does not substitute Go behavior for iOS behavior.
The fixture server permits undersized test keys with FIPS mode off, without
changing any application runtime setting or adding a production dependency.
