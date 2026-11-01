import Foundation
import Testing
@testable import KyAuth

struct ThemeMigrationTests {
    @Test func freshInstallIsBusnesFollowingTheSystem() {
        #expect(ThemeChoice(storedPair: nil, storedAppearance: nil) == ThemeChoice(pair: .busnes, appearance: .system))
    }

    @Test func formerBusnesLightAndDarkForceThatHalf() {
        #expect(ThemeChoice(storedPair: nil, storedAppearance: "light") == ThemeChoice(pair: .busnes, appearance: .light))
        #expect(ThemeChoice(storedPair: nil, storedAppearance: "dark") == ThemeChoice(pair: .busnes, appearance: .dark))
        #expect(ThemeChoice(storedPair: nil, storedAppearance: "system") == ThemeChoice(pair: .busnes, appearance: .system))
    }

    @Test func unknownAppearanceFollowsTheSystem() {
        #expect(ThemeChoice(storedPair: nil, storedAppearance: "oled") == ThemeChoice())
        #expect(ThemeChoice(storedPair: "ocean-pair", storedAppearance: "sepia") == ThemeChoice(pair: .ocean, appearance: .system))
    }

    @Test func removedOrUnknownPairResetsToBusnesFollowingTheSystem() {
        for removed in ["tropics", "tropic-night", "coffee", "cyber-punk", "neon-purple", "space", "sky", "sun", "cyber", "oled", "", "Busnes"] {
            #expect(ThemeChoice(storedPair: removed, storedAppearance: "dark") == ThemeChoice(), "\(removed)")
        }
    }

    @Test func everySavedPairRoundTrips() {
        for pair in ThemePair.allCases {
            for appearance in Appearance.allCases {
                #expect(ThemeChoice(storedPair: pair.rawValue, storedAppearance: appearance.rawValue) == ThemeChoice(pair: pair, appearance: appearance))
            }
        }
    }

    @Test func pairIDsAreKyUISuiteIDs() {
        #expect(ThemePair.allCases.map(\.rawValue) == ["busnes-pair", "matter-pair", "ocean-pair", "forest-pair", "ky-pair", "nord-pair"])
        #expect(ThemePair.allCases.map(\.title) == ["Busnes", "Matter", "Ocean", "Forest", "Ky", "Nord"])
    }

    @Test func readsBothKeysFromDefaults() throws {
        let name = "ThemeMigrationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("dark", forKey: Appearance.defaultsKey)
        #expect(ThemeChoice(defaults: defaults) == ThemeChoice(pair: .busnes, appearance: .dark))
        defaults.set("nord-pair", forKey: ThemePair.defaultsKey)
        #expect(ThemeChoice(defaults: defaults) == ThemeChoice(pair: .nord, appearance: .dark))
        defaults.set("cyber-punk", forKey: ThemePair.defaultsKey)
        #expect(ThemeChoice(defaults: defaults) == ThemeChoice())
    }

    @Test func busnesAccentIsTheGlobalAccentColor() {
        #expect(ThemePair.busnes.assetName(.accent) == "AccentColor")
        #expect(ThemePair.busnes.assetName(.background) == "BusnesBackground")
        #expect(ThemePair.forest.assetName(.successSoft) == "ForestSuccessSoft")
    }
}
