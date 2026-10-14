#!/usr/bin/env bash
# Runs KyAuthTests/PushCryptoTests.swift on a host without Xcode (needs Docker): builds Shared/PushCrypto.swift
# and KyAuth/Mfa/MfaChallenge.swift unchanged except `import CryptoKit` -> `import Crypto` (swift-crypto,
# CryptoKit's API on Linux). It proves the RFC 8291 code, not CryptoKit itself or anything on a device.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
# A fresh private directory each run: a fixed path in a shared temp directory could be planted by
# another user, and the writes below would follow its symlinks.
work="$(mktemp -d "${TMPDIR:-/tmp}/kyauth-push-crypto-check.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Sources/KyAuth" "$work/Tests/KyAuthTests"
sed 's/^import CryptoKit$/import Crypto/' "$repo/Shared/PushCrypto.swift" > "$work/Sources/KyAuth/PushCrypto.swift"
cp "$repo/KyAuth/Mfa/MfaChallenge.swift" "$work/Sources/KyAuth/"
cp "$repo/KyAuthTests/PushCryptoTests.swift" "$work/Tests/KyAuthTests/"
cat > "$work/Sources/KyAuth/Stubs.swift" <<'SWIFT'
// Stand-ins for app types MfaChallenge.swift touches; nothing here is under test.
import Foundation
enum PairingError: Error, Equatable { case invalid(String) }
struct PairedAccount {
    var serverUrl: String
    var deviceId: String
    var deviceName: String
    var username: String? = nil
    var userId: String? = nil
}
enum KeychainCodable {
    static func load<T: Decodable>(_ type: T.Type, _ account: String) -> T? { nil }
    static func save<T: Encodable>(_ value: T, _ account: String) throws {}
}
enum Keychain { static func delete(_ account: String) {} }
SWIFT
sed -n '/^extension String {/,/^}/p' "$repo/KyAuth/Pairing/QrPairing.swift" >> "$work/Sources/KyAuth/Stubs.swift"
cat > "$work/Package.swift" <<'SWIFT'
// swift-tools-version:6.0
import PackageDescription
let package = Package(
    name: "KyAuthPushCheck",
    dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")],
    targets: [
        .target(name: "KyAuth", dependencies: [.product(name: "Crypto", package: "swift-crypto")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "KyAuthTests", dependencies: ["KyAuth"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
SWIFT
# As this user, so the build output it leaves in $work is ours to delete.
docker run --rm --memory=6g --user "$(id -u):$(id -g)" -e HOME=/work/.home \
    -v "$work:/work" -w /work swift:6.1 swift test 2>&1
