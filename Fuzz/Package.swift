// swift-tools-version: 6.2
//
// Linux-only libFuzzer harness for the app's QR code parsers. Not part of the
// Xcode project. Apple's toolchain ships no libFuzzer for Swift, so this
// builds with the swift.org toolchain (`.github/workflows/fuzz.yml`):
//
//   swift build -c release --product FuzzScannedCode \
//     -Xswiftc -sanitize=fuzzer,address -Xswiftc -parse-as-library
//
// Release configuration on purpose: without DEBUG, PairingEndpoint accepts
// HTTPS only, as the shipping app does. swift-crypto (exact version, pinned
// by revision in Package.resolved) stands in for CryptoKit.

import PackageDescription

let package = Package(
    name: "KyAuthFuzz",
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "5.1.1"),
    ],
    targets: [
        .target(
            name: "CryptoKit",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")]
        ),
        .executableTarget(
            name: "FuzzScannedCode",
            dependencies: ["CryptoKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
