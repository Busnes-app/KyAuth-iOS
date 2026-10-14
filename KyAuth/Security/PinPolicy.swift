import CommonCrypto
import Foundation
import LocalAuthentication

enum PinPolicy {
    static let minLength = 4
    static let maxLength = 12

    private static let weak: Set<String> = [
        "0000", "1111", "2222", "3333", "4444", "5555", "6666", "7777", "8888", "9999",
        "1234", "4321", "1212", "0123", "9876", "2580", "1357", "2468",
        "000000", "111111", "222222", "333333", "444444", "555555", "666666", "777777", "888888", "999999",
        "123456", "654321", "121212", "123123", "112233", "696969",
        "12345678", "87654321", "11223344", "12341234",
    ]

    /// Nil when the PIN is acceptable, else the reason it is not.
    static func validate(_ pin: String) -> String? {
        if pin.count < minLength { return "PIN must be at least \(minLength) digits" }
        if pin.count > maxLength { return "PIN cannot exceed \(maxLength) digits" }
        if !pin.allSatisfy({ $0.isASCII && $0.isNumber }) { return "PIN must contain only numbers" }
        if weak.contains(pin) { return "This PIN is too common and easily guessed" }
        if isRun(pin) { return "PIN cannot be a sequence of consecutive numbers" }
        return nil
    }

    private static func isRun(_ pin: String) -> Bool {
        let digits = pin.compactMap(\.wholeNumberValue)
        guard digits.count >= 4 else { return false }
        let deltas = zip(digits, digits.dropFirst()).map { $1 - $0 }
        return deltas.allSatisfy { $0 == 1 } || deltas.allSatisfy { $0 == -1 } || deltas.allSatisfy { $0 == 0 }
    }
}

struct PinFailureState: Codable, Equatable {
    var failedAttempts = 0
    /// System uptime (`ProcessInfo.systemUptime`) before which no PIN is accepted. Uptime ignores
    /// clock changes but restarts at boot; `normalized` handles the restart.
    var retryAfterUptime: TimeInterval = 0
}

/// Delays of 0, 5, 30 and 300 seconds after failures one to four; the fifth failure wipes.
/// Every `now` is system uptime, so setting the clock forward skips no delay.
enum PinFailurePolicy {
    static let wipeAfterAttempts = 5

    static func registerFailure(_ state: PinFailureState, now: TimeInterval) -> PinFailureState {
        let attempts = state.failedAttempts + 1
        return PinFailureState(failedAttempts: attempts, retryAfterUptime: now + delaySeconds(attempts))
    }

    /// After a restart uptime begins again near zero, so a deadline further away than the delay itself
    /// can only come from before the restart: the full delay starts again from now. A restart never
    /// shortens a delay.
    static func normalized(_ state: PinFailureState, now: TimeInterval) -> PinFailureState {
        let delay = delaySeconds(state.failedAttempts)
        guard state.retryAfterUptime - now > delay else { return state }
        return PinFailureState(failedAttempts: state.failedAttempts, retryAfterUptime: now + delay)
    }

    static func mayTry(_ state: PinFailureState, now: TimeInterval) -> Bool {
        state.failedAttempts < wipeAfterAttempts && now >= state.retryAfterUptime
    }

    static func secondsUntilRetry(_ state: PinFailureState, now: TimeInterval) -> Int64 {
        Int64(max(0, (state.retryAfterUptime - now).rounded(.up)))
    }

    static func attemptsRemaining(_ state: PinFailureState) -> Int {
        max(0, wipeAfterAttempts - state.failedAttempts)
    }

    static func mustWipe(_ state: PinFailureState) -> Bool {
        state.failedAttempts >= wipeAfterAttempts
    }

    private static func delaySeconds(_ attempt: Int) -> TimeInterval {
        switch attempt {
        case 2: 5
        case 3: 30
        case 4: 300
        default: 0
        }
    }
}

/// The optional PIN, a second local factor after Face ID. Its verifier is a protected Keychain item,
/// read with the same evaluated context that releases the vault key.
enum PinStore {
    private static let verifierAccount = "pin-verifier"
    private static let failuresAccount = "pin-failures"
    private static let enabledAccount = "pin-enabled"
    static let iterations: UInt32 = 310_000

    private struct Verifier: Codable {
        let salt: Data
        let hash: Data
        let iterations: UInt32
    }

    /// Whether a PIN is set; readable without a prompt.
    static var isEnabled: Bool { Keychain.exists(enabledAccount) }

    /// False when the PIN is on but its verifier is gone: iOS destroys it with the passcode, along
    /// with the vault key and the device key it guarded, so no PIN can ever match again.
    static var hasVerifier: Bool { Keychain.exists(verifierAccount) }

    static func set(_ pin: String) throws {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let verifier = Verifier(salt: salt, hash: derive(pin, salt: salt, iterations: iterations), iterations: iterations)
        try Keychain.setProtected(try JSONEncoder().encode(verifier), for: verifierAccount)
        try Keychain.set(Data([1]), for: enabledAccount)
        resetFailures()
    }

    static func remove() {
        Keychain.delete(verifierAccount)
        Keychain.delete(enabledAccount)
        resetFailures()
    }

    static func verify(_ pin: String, context: LAContext) throws -> Bool {
        guard let data = try Keychain.get(verifierAccount, context: context),
              let verifier = try? JSONDecoder().decode(Verifier.self, from: data)
        else { return false }
        let candidate = derive(pin, salt: verifier.salt, iterations: verifier.iterations)
        return constantTimeEqual(candidate, verifier.hash)
    }

    static var failures: PinFailureState {
        KeychainCodable.load(PinFailureState.self, failuresAccount) ?? PinFailureState()
    }

    static func saveFailures(_ state: PinFailureState) {
        try? KeychainCodable.save(state, failuresAccount)
    }

    static func resetFailures() {
        Keychain.delete(failuresAccount)
    }

    static func derive(_ pin: String, salt: Data, iterations: UInt32) -> Data {
        var out = Data(count: 32)
        let password = Array(pin.utf8)
        _ = out.withUnsafeMutableBytes { outBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2), password.map { Int8(bitPattern: $0) }, password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                    outBytes.bindMemory(to: UInt8.self).baseAddress, 32
                )
            }
        }
        return out
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
