# Contributing to KyAuth for iOS

KyAuth is the KyIdentity authenticator for iPhone and iPad: TOTP codes, Push MFA approvals and KyIdentity sign-on. Contributions must keep authenticator secrets on the device and keep every sign-in approval behind an explicit human action.

## Before contributing

Read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) and [SECURITY.md](SECURITY.md),
the [README](README.md), and any AGENTS.md in the subtree you are about to
touch. Open an issue before proposing a feature larger than a bug fix or
documentation change.

Keep changes small, reuse existing code, and fix the shared root cause rather
than the reported symptom. New non-trivial logic ships with a runnable test or
self-check.

## Security requirements

- TOTP seeds and push-approval keys stay on the device in the Keychain / Secure Enclave; never transmit them off-device or write them to logs or crash reports.
- A sign-in or MFA approval happens only on an explicit user action, never automatically; a notification alone is not consent.
- Do not add telemetry, phone-home, analytics, or unconfigured third-party
  services.
- Do not add silent security fallbacks; fail closed with a readable error and a
  remediation step.
- Name and document any security trade-off in [SECURITY.md](SECURITY.md) before
  it merges.

## Verification

Run the checks that apply to the files you changed, and the repository's
full required checks before hand-off. Record the exact commands and their
results in the pull request.

The complete native suite uses `bash scripts/test-ios.sh DISPOSABLE_SIMULATOR_UUID`;
its loopback TLS fixtures need Go 1.26.10 and the documented test-host mapping.
See [fixture setup](scripts/tls-fixtures/README.md). The ordinary production
HTTPClient and trust policy remain in use during those tests. A successful run writes
a `coverage.json` app line-count report next to its result bundle; absent or
unexercised extension coverage is reported separately. Usable reports from failed
tests or incomplete runs retain explicit names; invalid or failed exports are
removed. An evidence-export failure fails the job even when native tests pass.
Shared sources compile into both products, so their counts are not additive. CI is configured to build the app
and extension in Release even if tests fail; these additions await native CI evidence.

Swift warnings are errors (`SWIFT_TREAT_WARNINGS_AS_ERRORS`). Fix the warning, or
document a false positive in the source — do not silence the diagnostic. This
also applies to the CodeQL build. Swift 5 mode without complete concurrency
diagnostics does not yet establish OpenSSF `warnings_strict`.

## AI attribution

AI-assisted contributions are welcome; undisclosed ones are not. Disclose
material AI assistance in the pull request — the tool, what it changed, and what
you personally ran, read, and verified — and add a commit trailer naming any
tool that materially contributed. You are the author of the code you submit for
every purpose, regardless of how it was produced.

## Pull requests

Branch off `master` with a focused name, and use a Conventional Commit subject
(`fix:`, `feat:`, `docs:`, `refactor:`, `test:`, or `chore:`). The pull request
explains why the change exists, the verification performed, the security impact,
and any known limitations.

Every pull request gets an adversarial review pass; see
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md#hostile-reviews-are-about-code-never-people)
for what that is and the boundary it keeps.

## Licence

KyAuth for iOS is licensed under the MIT License. See [LICENSE.txt](LICENSE.txt).

