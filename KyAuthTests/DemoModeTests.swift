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

    @Test func challengeOffersTheMatchAmongThreeDecoys() {
        for seed in 0..<200 {
            var generator = SeededGenerator(state: UInt64(seed))
            let challenge = DemoMode.challenge(nowMs: 1_000, using: &generator)
            #expect(challenge.options.count == 4)
            #expect(challenge.options.contains(challenge.matchDigits))
            #expect(challenge.options.allSatisfy(MfaMessage.isTwoDigits))
            #expect(challenge.expiresAtEpochMs == 1_000 + DemoMode.pushLifetimeMs)
            #expect(challenge.serverUrl == DemoMode.serverUrl)
        }
    }

    @Test func resultFollowsTheServerRules() {
        var generator = SeededGenerator(state: 7)
        let challenge = DemoMode.challenge(nowMs: 1_000_000, using: &generator)
        let live = Date(timeIntervalSince1970: 1_000)
        let wrong = challenge.decoyDigits[0]
        #expect(DemoMode.result(challenge, approve: true, digits: challenge.matchDigits, now: live) == "Sign-in approved")
        #expect(DemoMode.result(challenge, approve: true, digits: wrong, now: live).hasPrefix("Sign-in denied"))
        #expect(DemoMode.result(challenge, approve: false, digits: "", now: live) == "Sign-in denied")
        #expect(DemoMode.result(challenge, approve: true, digits: challenge.matchDigits, now: .distantFuture) == "Sign-in request expired")
    }

    @Test func demoRunsInMemoryAndLockingEndsIt() throws {
        let model = AppModel(account: nil)
        model.startDemo()
        #expect(model.isDemo)
        #expect(model.lockState == .unlocked)
        #expect(model.entries.map(\.id) == DemoMode.entries().map(\.id))

        try model.addEntry(try TotpEntry(title: "Added", secretBase32: "JBSWY3DPEHPK3PXP"))
        #expect(model.entries.count == 4)

        model.lock()
        #expect(!model.isDemo)
        #expect(model.lockState == .locked)
        #expect(model.entries.isEmpty)
        #expect(model.pendingChallenge == nil)
    }

    @Test func pairedPhoneNeverRunsTheDemo() {
        let paired = PairedAccount(serverUrl: "https://id.example.com", deviceId: "d1", deviceName: "iPhone")
        let model = AppModel(account: paired)
        model.startDemo()
        #expect(!model.isDemo)
        #expect(model.lockState == .locked)
    }
}
