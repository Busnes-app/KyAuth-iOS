import Foundation
import Testing
import UIKit
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
        model.copy(decoded)
        #expect(model.notice == TotpError.shortSecret.localizedDescription)
        var renamed = original[0]
        renamed.title = "Renamed"
        try model.updateEntry(renamed)
        #expect(model.entries[0].title == "Renamed")
        #expect(model.entries[0].secretBase32 == original[0].secretBase32)
        model.lock()
    }

    /// Copy exists to paste in another app, and switching to it locks KyAuth.
    @Test func leavingKyAuthKeepsACopiedCodeAndOtherLocksClearIt() throws {
        let model = AppModel(account: nil)
        model.startDemo()
        let entry = model.entries[0]
        let now = Date()
        model.copy(entry, now: now)
        model.lock(leavingApp: true)
        #expect(UIPasteboard.general.string == (try TotpGenerator.code(entry, at: Int64(now.timeIntervalSince1970))))

        model.startDemo()
        model.copy(entry)
        model.lock()
        #expect(UIPasteboard.general.string == nil)
    }

    /// A tap just after a period ends copies the new period's code, not the one last drawn.
    @Test func copyTakesTheCodeAtTheMomentOfCopying() throws {
        let model = AppModel(account: nil)
        model.startDemo()
        let entry = model.entries[0]
        // The start of the current period, so the copied code has not expired yet.
        let start = Int64(Date().timeIntervalSince1970) / entry.periodSeconds * entry.periodSeconds
        model.copy(entry, now: Date(timeIntervalSince1970: TimeInterval(start)))
        #expect(UIPasteboard.general.string == (try TotpGenerator.code(entry, at: start)))
        #expect(UIPasteboard.general.string != (try TotpGenerator.code(entry, at: start - 1)))
        model.lock()
    }

    /// Lock, the idle lock and the PIN screen's Cancel must not unlock again on their own.
    @Test func theLockScreenPromptsOnlyAtLaunchAndAfterLeaving() {
        let model = AppModel(account: nil)
        #expect(model.takeAutoUnlock())
        #expect(!model.takeAutoUnlock())
        model.lock(leavingApp: true)
        #expect(model.takeAutoUnlock())
        model.lock(leavingApp: true)
        model.lock()
        #expect(!model.takeAutoUnlock())
    }

    @Test func pairedPhoneNeverRunsTheDemo() {
        let paired = PairedAccount(serverUrl: "https://id.example.com", deviceId: "d1", deviceName: "iPhone")
        let model = AppModel(account: paired)
        model.startDemo()
        #expect(!model.isDemo)
        #expect(model.lockState == .locked)
    }
}
