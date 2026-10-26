import Foundation
import Testing
@testable import KyAuth

@MainActor
struct DemoModeTests {
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    @Test func demoServerCanNeverResolve() {
        #expect(URL(string: DemoMode.serverUrl)?.host()?.hasSuffix(".invalid") == true)
    }

    @Test func demoEntriesGenerateCodes() throws {
        let entries = DemoMode.entries()
        #expect(Set(entries.map(\.id)).count == entries.count)
        for entry in entries {
            #expect(try TotpGenerator.code(entry, at: 1_700_000_000).count == 6)
        }
    }

    @Test func browserDigitsAreTwoDigits() {
        for seed in 0..<200 {
            var generator = SeededGenerator(state: UInt64(seed))
            #expect(MfaMessage.isTwoDigits(DemoMode.browserDigits(using: &generator)))
        }
        let challenge = DemoMode.challenge(nowMs: 1_000)
        #expect(challenge.expiresAtEpochMs == 1_000 + DemoMode.pushLifetimeMs)
        #expect(challenge.serverUrl == DemoMode.serverUrl)
    }

    @Test func resultFollowsTheServerRules() {
        let challenge = DemoMode.challenge(nowMs: 1_000_000)
        let live = Date(timeIntervalSince1970: 1_000)
        #expect(DemoMode.result(challenge, approve: true, digits: "42", browserDigits: "42", now: live) == "Sign-in approved")
        #expect(DemoMode.result(challenge, approve: true, digits: "24", browserDigits: "42", now: live).hasPrefix("Sign-in denied"))
        #expect(DemoMode.result(challenge, approve: false, digits: "", browserDigits: "42", now: live) == "Sign-in denied")
        #expect(DemoMode.result(challenge, approve: true, digits: "42", browserDigits: "42", now: .distantFuture) == "Sign-in request expired")
    }

    @Test func demoRunsInMemoryAndLockingEndsIt() throws {
        let model = AppModel(account: nil)
        model.startDemo()
        #expect(model.isDemo)
        #expect(model.lockState == .unlocked)
        #expect(model.entries.map(\.id) == DemoMode.entries().map(\.id))

        try model.addEntry(try TotpEntry(title: "Added", secretBase32: "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"))
        #expect(model.entries.count == 4)

        model.lock()
        #expect(!model.isDemo)
        #expect(model.lockState == .locked)
        #expect(model.entries.isEmpty)
        #expect(model.pendingChallenge == nil)
    }

    @Test func modelRefusesWeakAddsReplacementsAndCopies() throws {
        let model = AppModel(account: nil)
        model.startDemo()
        let original = model.entries
        var weak = original[0]
        weak.secretBase32 = "MY"
        // A decoded/mutable entry bypasses the constructor, but never the model boundary.
        let decoded = try JSONDecoder().decode(TotpEntry.self, from: JSONEncoder().encode(weak))
        #expect(throws: TotpError.shortSecret) { try model.addEntry(decoded) }
        #expect(throws: TotpError.shortSecret) { try model.updateEntry(decoded) }
        #expect(model.entries == original)
        model.copy("123456", entry: decoded)
        #expect(model.notice == TotpError.shortSecret.localizedDescription)
        var renamed = original[0]
        renamed.title = "Renamed"
        try model.updateEntry(renamed)
        #expect(model.entries[0].title == "Renamed")
        #expect(model.entries[0].secretBase32 == original[0].secretBase32)
        model.lock()
    }

    @Test func pairedPhoneNeverRunsTheDemo() {
        let paired = PairedAccount(serverUrl: "https://id.example.com", deviceId: "d1", deviceName: "iPhone")
        let model = AppModel(account: paired)
        model.startDemo()
        #expect(!model.isDemo)
        #expect(model.lockState == .locked)
    }
}
