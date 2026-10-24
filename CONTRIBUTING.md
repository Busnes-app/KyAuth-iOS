# Contributing to KyAuth for iOS

KyAuth holds TOTP secrets and the device key KyIdentity trusts to approve sign-ins. A
contribution must keep the contracts in [KyAuth/AGENTS.md](KyAuth/AGENTS.md) and the argument in
[docs/ASSURANCE-CASE.md](docs/ASSURANCE-CASE.md) true.

## How to contribute

- **Bugs and ideas:** open an issue at <https://github.com/Busnes-app/KyAuth-iOS/issues>.
  Report vulnerabilities privately instead: the repository's **Security** tab, **Report a
  vulnerability** ([policy](https://github.com/Busnes-app/.github/blob/main/SECURITY.md)).
- **Changes:** branch off `master`, open a pull request against `master`, and describe what you
  ran. Every change lands through a pull request.
- **Docs follow the DOX chain:** read every `AGENTS.md` from the root to the files you touch
  before editing, and update the nearest one when a contract changes ([AGENTS.md](AGENTS.md)).
- A change that moves a trust boundary or a security requirement updates
  [docs/ASSURANCE-CASE.md](docs/ASSURANCE-CASE.md) in the same pull request.

## Tests

Add a focused test for non-trivial logic, in `KyAuthTests/`. Run the suite before you open the
pull request (choose an installed simulator):

```sh
xcodebuild -project KyAuth.xcodeproj -scheme KyAuth \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

The repository has no CI, so this run is the gate. Say in the pull request which simulator you
used and what you could not check there: APNs delivery, Secure Enclave signing, App Attest, Face
ID, the camera, the notification extension and the KyPost sign-on round trip need a physical
device ([README](README.md#build-and-verification)).

## Coding standard

| Language | Style guide | Enforced by |
|---|---|---|
| Swift | The [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) | The Swift compiler (Swift 5 language mode) when you build and test; no linter and no CI |

Nothing checks style automatically. Beyond the compiler: keep to the naming and comment density of
the file you are editing, use no third-party packages, keep security checks fail-closed, and
follow the UI rules in [KyAuth/AGENTS.md](KyAuth/AGENTS.md#work-guidance).

## Licence

KyAuth is MIT-licensed ([LICENSE.txt](LICENSE.txt)). By contributing you agree that your
contribution is licensed the same way.
