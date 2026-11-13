// Linux has no CryptoKit. swift-crypto is Apple's implementation of the same
// API, so this module lets the app's `import CryptoKit` compile unchanged.
@_exported import Crypto
