import Foundation

/// The six suite palettes (ky-ui `THEME_PAIRS`), each a light and a dark half. Their colors are
/// asset catalog color sets written by `scripts/theme-colorsets.py`. Raw values are ky-ui's pair
/// IDs and are saved: never rename one.
enum ThemePair: String, CaseIterable, Identifiable {
    case busnes = "busnes-pair"
    case matter = "matter-pair"
    case ocean = "ocean-pair"
    case forest = "forest-pair"
    case ky = "ky-pair"
    case nord = "nord-pair"

    static let defaultsKey = "theme-pair"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .busnes: "Busnes"
        case .matter: "Matter"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .ky: "Ky"
        case .nord: "Nord"
        }
    }

    /// `<Title><Role>`, except Busnes's accent, which is `AccentColor`, the app's global accent.
    func assetName(_ role: ThemeRole) -> String {
        self == .busnes && role == .accent ? "AccentColor" : title + role.rawValue
    }
}

enum ThemeRole: String, CaseIterable {
    case background = "Background"
    case surface = "Surface"
    case accent = "Accent"
    /// Label color on a filled accent button.
    case onAccent = "OnAccent"
    case danger = "Danger"
    case warning = "Warning"
    case success = "Success"
    /// 12% of the status over the surface, behind text in that status color.
    case dangerSoft = "DangerSoft"
    case warningSoft = "WarningSoft"
    case successSoft = "SuccessSoft"
}

/// Whether the pair follows the system or shows one half. Stored in `UserDefaults`; the raw values
/// predate the pairs, when `light` and `dark` were Busnes Light and Busnes Dark.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let defaultsKey = "appearance"

    var id: String { rawValue }

    /// An absent or unknown stored value follows the system.
    init(stored: String?) {
        self = stored.flatMap(Appearance.init(rawValue:)) ?? .system
    }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// The saved theme: a pair and its appearance.
struct ThemeChoice: Equatable {
    var pair: ThemePair = .busnes
    var appearance: Appearance = .system

    /// Reads a saved choice. Before the pairs, KyAuth saved only the appearance, so a saved
    /// `light` or `dark` with no pair (Busnes Light, Busnes Dark) is Busnes with that half forced.
    /// A saved pair that is not one of the six resets to Busnes following the system.
    init(storedPair: String?, storedAppearance: String?) {
        let appearance = Appearance(stored: storedAppearance)
        guard let storedPair else {
            self.init(pair: .busnes, appearance: appearance)
            return
        }
        guard let pair = ThemePair(rawValue: storedPair) else {
            self.init()
            return
        }
        self.init(pair: pair, appearance: appearance)
    }

    init(pair: ThemePair = .busnes, appearance: Appearance = .system) {
        self.pair = pair
        self.appearance = appearance
    }

    init(defaults: UserDefaults) {
        self.init(
            storedPair: defaults.string(forKey: ThemePair.defaultsKey),
            storedAppearance: defaults.string(forKey: Appearance.defaultsKey)
        )
    }
}
