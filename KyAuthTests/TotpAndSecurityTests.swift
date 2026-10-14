import CryptoKit
import Foundation
import Testing
@testable import KyAuth

@MainActor
struct TotpGeneratorTests {
    // RFC 6238 Appendix B vectors.
    @Test func rfc6238() throws {
        let sha1 = try TotpEntry(title: "t", secretBase32: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", digits: 8)
        #expect(try TotpGenerator.code(sha1, at: 59) == "94287082")
        #expect(try TotpGenerator.code(sha1, at: 1_111_111_109) == "07081804")
        let sha256 = try TotpEntry(
            title: "t", secretBase32: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA", digits: 8, algorithm: .sha256
        )
        #expect(try TotpGenerator.code(sha256, at: 59) == "46119246")
        let sha512 = try TotpEntry(
            title: "t",
            secretBase32: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA",
            digits: 8, algorithm: .sha512
        )
        #expect(try TotpGenerator.code(sha512, at: 59) == "90693936")
    }

    @Test func formattingAndCountdown() throws {
        #expect(TotpGenerator.formatted("123456") == "123 456")
        #expect(TotpGenerator.formatted("12345678") == "12345678")
        let entry = try TotpEntry(title: "t", secretBase32: "JBSWY3DPEHPK3PXP")
        #expect(TotpGenerator.secondsRemaining(entry, at: 59) == 1)
        #expect(TotpGenerator.secondsRemaining(entry, at: 60) == 30)
    }

    @Test func refusesUnusableSecrets() {
        #expect(!TotpGenerator.isUsableSecret("A"))
        #expect(!TotpGenerator.isUsableSecret("01"))
        #expect(!TotpGenerator.isUsableSecret(""))
        #expect(TotpGenerator.isUsableSecret("jbsw y3dp ===="))
        #expect(throws: TotpError.self) { try TotpEntry(title: "t", secretBase32: "A") }
        #expect(throws: TotpError.self) { try TotpEntry(title: " ", secretBase32: "JBSWY3DP") }
        #expect(throws: TotpError.self) { try TotpEntry(title: "t", secretBase32: "JBSWY3DP", digits: 9) }
    }
}

@MainActor
struct TotpUriParserTests {
    @Test func parsesIssuerLabelAndParameters() throws {
        let entry = try TotpUriParser.parse(
            "otpauth://totp/ACME%20Co:ada@example.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME%20Co&algorithm=SHA512&digits=8&period=60"
        )
        #expect(entry.title == "ACME Co (ada@example.com)")
        #expect(entry.issuer == "ACME Co")
        #expect(entry.algorithm == .sha512)
        #expect(entry.digits == 8)
        #expect(entry.periodSeconds == 60)
    }

    @Test func labelWithoutColon() throws {
        #expect(try TotpUriParser.parse("otpauth://totp/ada?secret=JBSWY3DPEHPK3PXP&issuer=ACME").title == "ACME (ada)")
        #expect(try TotpUriParser.parse("otpauth://totp/ACME?secret=JBSWY3DPEHPK3PXP&issuer=acme").title == "ACME")
        #expect(try TotpUriParser.parse("otpauth://totp/?secret=JBSWY3DPEHPK3PXP").title == "Account")
    }

    @Test func suppliedParametersMustBeSupported() throws {
        let base = "otpauth://totp/a?secret=JBSWY3DPEHPK3PXP"
        for bad in ["&algorithm=SHA3", "&algorithm=MD5", "&digits=abc", "&digits=9", "&digits=0", "&period=abc", "&period=-30", "&period=0", "&digits", "&period", "&algorithm", "&digits=", "&algorithm="] {
            #expect(throws: TotpError.self) { try TotpUriParser.parse(base + bad) }
        }
        let defaults = try TotpUriParser.parse(base)
        #expect(defaults.algorithm == .sha1 && defaults.digits == 6 && defaults.periodSeconds == 30)
        #expect(try TotpUriParser.parse(base + "&algorithm=sha256").algorithm == .sha256)
    }

    @Test func refusesOtherSchemesHotpAndMissingSecret() {
        #expect(throws: TotpError.self) { try TotpUriParser.parse("https://example.com") }
        #expect(throws: TotpError.self) { try TotpUriParser.parse("otpauth://hotp/a?secret=JBSWY3DP&counter=1") }
        #expect(throws: TotpError.self) { try TotpUriParser.parse("otpauth://totp/a?issuer=x") }
    }
}

@MainActor
struct TotpVaultTests {
    @Test func roundTripsAndRefusesTheWrongKey() throws {
        let key = SymmetricKey(size: .bits256)
        let entries = [try TotpEntry(title: "A", secretBase32: "JBSWY3DPEHPK3PXP", url: "https://a.example", notes: "n")]
        let sealed = try TotpVault.seal(entries, key: key)
        #expect(try TotpVault.open(sealed, key: key) == entries)
        #expect(throws: VaultError.self) { try TotpVault.open(sealed, key: SymmetricKey(size: .bits256)) }
        var tampered = sealed
        tampered[tampered.count - 20] ^= 1
        #expect(throws: VaultError.self) { try TotpVault.open(tampered, key: key) }
    }

    @Test func onlyAnAbsentVaultLoadsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = SymmetricKey(size: .bits256)
        #expect(try TotpVault(file: directory.appendingPathComponent("absent.bin")).load(key: key).isEmpty)

        let empty = directory.appendingPathComponent("empty.bin")
        try Data().write(to: empty)
        #expect(throws: VaultError.self) { try TotpVault(file: empty).load(key: key) }

        // A directory where the file should be cannot be read.
        let unreadable = directory.appendingPathComponent("unreadable.bin")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        #expect(throws: VaultError.self) { try TotpVault(file: unreadable).load(key: key) }
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func fileIsExcludedFromBackupAndEmptyWhenAbsent() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("v.bin")
        let vault = TotpVault(file: file)
        let key = SymmetricKey(size: .bits256)
        #expect(try vault.load(key: key).isEmpty)
        try vault.save([try TotpEntry(title: "A", secretBase32: "JBSWY3DPEHPK3PXP")], key: key)
        #expect(try vault.load(key: key).count == 1)
        #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        vault.delete()
    }

    @Test func aVaultWithoutItsKeyIsNeverGivenANewOne() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var vault = TotpVault(file: directory.appendingPathComponent("v.bin"))
        vault.keyAccount = "test-\(UUID().uuidString)"
        try Data([1, 2, 3]).write(to: vault.file)

        #expect(throws: VaultError.keyMissing) { try vault.ensureKey() }
        #expect(!Keychain.exists(vault.keyAccount))
    }
}

@MainActor
struct PinTests {
    @Test func policy() {
        #expect(PinPolicy.validate("482915") == nil)
        #expect(PinPolicy.validate("123") != nil)
        #expect(PinPolicy.validate("1234567890123") != nil)
        #expect(PinPolicy.validate("12a4") != nil)
        #expect(PinPolicy.validate("2580") != nil)
        #expect(PinPolicy.validate("3456") != nil)
        #expect(PinPolicy.validate("9876") != nil)
        #expect(PinPolicy.validate("7777777") != nil)
    }

    @Test func failureLadderWipesOnTheFifth() {
        var state = PinFailureState()
        let delays: [Int64] = [0, 5, 30, 300]
        var now: TimeInterval = 1000
        for (index, delay) in delays.enumerated() {
            #expect(PinFailurePolicy.mayTry(state, now: now))
            state = PinFailurePolicy.registerFailure(state, now: now)
            #expect(PinFailurePolicy.secondsUntilRetry(state, now: now) == delay)
            #expect(PinFailurePolicy.attemptsRemaining(state) == 4 - index)
            #expect(!PinFailurePolicy.mustWipe(state))
            now += TimeInterval(delay)
        }
        state = PinFailurePolicy.registerFailure(state, now: now)
        #expect(PinFailurePolicy.mustWipe(state))
        #expect(!PinFailurePolicy.mayTry(state, now: now + 10_000))
    }

    /// A record saved before the uptime change keeps its count, and its delay starts again in full.
    @Test func anOlderFailureRecordKeepsItsCount() throws {
        let legacy = Data(#"{"failedAttempts":4,"retryAfterEpochSeconds":1760000000}"#.utf8)
        let state = PinFailurePolicy.normalized(try JSONDecoder().decode(PinFailureState.self, from: legacy), now: 100)
        #expect(state.failedAttempts == 4)
        #expect(!PinFailurePolicy.mayTry(state, now: 100))
        #expect(PinFailurePolicy.secondsUntilRetry(state, now: 100) == 300)
        #expect(PinFailurePolicy.mustWipe(PinFailurePolicy.registerFailure(state, now: 400)))

        // The migrated state is saved again, so it must encode and read back unchanged.
        #expect(try JSONDecoder().decode(PinFailureState.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test func aRestartNeverShortensTheDelay() {
        // Fourth failure at uptime 50,000 s: 300 s to wait.
        var state = PinFailureState()
        for _ in 0..<4 { state = PinFailurePolicy.registerFailure(state, now: 50_000) }
        #expect(PinFailurePolicy.normalized(state, now: 50_100) == state)

        // After a restart uptime is near zero: the whole delay starts again, not 50,000 s.
        let restarted = PinFailurePolicy.normalized(state, now: 20)
        #expect(restarted.failedAttempts == 4)
        #expect(PinFailurePolicy.secondsUntilRetry(restarted, now: 20) == 300)
        #expect(!PinFailurePolicy.mayTry(restarted, now: 319))
        #expect(PinFailurePolicy.mayTry(restarted, now: 320))
    }

    @Test func derivationIsSaltedAndStable() {
        let salt = Data(repeating: 7, count: 16)
        let a = PinStore.derive("482915", salt: salt, iterations: 1000)
        #expect(a == PinStore.derive("482915", salt: salt, iterations: 1000))
        #expect(a != PinStore.derive("482916", salt: salt, iterations: 1000))
        #expect(a != PinStore.derive("482915", salt: Data(repeating: 8, count: 16), iterations: 1000))
        #expect(a.count == 32)
    }
}

@MainActor
struct IdleLockTests {
    @Test func expiresAfterTimeoutAndOnClockGoingBack() {
        var lock = IdleLock()
        let first = lock.expired(now: 100, timeout: 60)
        let recorded = lock.activity(now: 150, timeout: 60)
        let before = lock.expired(now: 209, timeout: 60)
        let after = lock.expired(now: 210, timeout: 60)
        let late = lock.activity(now: 300, timeout: 60)
        #expect(!first && recorded && !before && after && !late)
        var back = IdleLock()
        _ = back.activity(now: 100, timeout: 60)
        let wentBack = back.expired(now: 50, timeout: 60)
        #expect(wentBack)
    }

    @Test func minutes() {
        #expect(IdleLock.validatedMinutes(15) == 15)
        #expect(IdleLock.validatedMinutes(7) == 5)
        #expect(IdleLock.validatedMinutes(0) == 5)
    }
}

struct AppearanceTests {
    @Test func storedValueFallsBackToSystem() {
        #expect(Appearance(stored: nil) == .system)
        #expect(Appearance(stored: "Ocean") == .system)
        #expect(Appearance(stored: "light") == .light)
        #expect(Appearance(stored: "dark") == .dark)
    }
}
