# Native TLS key-policy regressions

These peers qualify the real app HTTPClient on a disposable iOS simulator.
The app retains native hostname/time/trust and ATS, adds a literal all-chain
RSA-2048/prime-EC-256 floor, and refuses redirects. No URLProtocol mock or
client trust override is used. Earlier unchanged-client native evidence accepted
RSA-2047 and sent application bytes; a green baseline was not a repair.

The standard-library Go server generates a shared RSA-3072 CA, seven-day peers,
weak RSA-1024/2047 at leaf/intermediate/root, directly trusted self-signed peers,
and strong RSA-2048/P-256/P-384/P-521 controls. Authority keys are discarded;
server private keys are public disposable test material. Generated keys/results
stay ignored under `.tls-fixtures/`, outside app and test bundles. Issuer roots
are omitted from wire chains; the client must build them from its trust store.

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
generated `root.pem`/`anchor-*.pem` there, and starts loopback-only listeners on
46100–46120. The untrusted control's root is never imported. It runs the complete
scheme and stops its owned fixture process on exit. The script never edits a
local hosts file or touches a physical device. Erase the disposable simulator
when done to remove its test anchors. CI uses an ephemeral macOS runner.

Results: `.tls-fixtures/results-*/TestResults.xcresult`, with public post-suite
counters in `fixture-stats.json` and the console. Fixture startup output stays
in `.tls-fixtures/server.log`. CI explicitly includes hidden paths when
uploading only the results directories; generated keys are outside that upload.
No request body/header or real credential is logged. A failed test run still
captures counters and retains its failing exit status.

## Required observations

- Security.framework must report literal RSA-2047 bits; rounded block size is
  logged separately and cannot implement the minimum.
- Twenty cases cover weak RSA at all chain positions/direct trust, seven strong
  controls, expired/wrong-host/untrusted peers, TLS1.0/1.1 refusal and TLS1.2/1.3
  success. Every case must reach its TCP listener. Strong controls succeed;
  rejected cases must receive zero application bytes and zero HTTP requests.
- `KYAUTH_TLS_POLICY` and the retained counters report those observations.
  `KYAUTH_TLS_REUSE` reports repeated requests and actual connection count;
  pooling is claimed only when observed. Redirect302 must reach the caller
  without contacting its target. The real app source is used throughout.

## Host calibration and limits

The Go suite verifies exact RSA/EC sizes, actual verified weak chain positions,
root omission, directly trusted peers, negotiated versions, keepalive, and zero
application bytes on invalid trust. The weak/TLS1.0/1.1 fixtures deliberately run
with FIPS mode off; this changes no application policy or production dependency.
It proves fixture usability, not iOS behavior. The native suite must pass before
a runtime repair is claimed. These local peers do not qualify a live deployment,
physical hardware or every supported OS version.
