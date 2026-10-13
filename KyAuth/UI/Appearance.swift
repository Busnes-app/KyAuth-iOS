import SwiftUI
import UIKit

/// Busnes Light and Busnes Dark (`BusnesBackground`, `BusnesSurface` and `AccentColor` in the asset
/// catalog), or whichever the system is using. Stored in `UserDefaults`.
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
        case .light: "Busnes Light"
        case .dark: "Busnes Dark"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Set on the window rather than through `preferredColorScheme`, so sheets, alerts and
    /// confirmation dialogs follow it and returning to System takes effect at once.
    @MainActor func apply() {
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}

/// A `Form` on the Busnes background with Busnes row surfaces.
struct BusnesForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { Group { content }.listRowBackground(Color.busnesSurface) }
            .scrollContentBackground(.hidden)
            .background(Color.busnesBackground)
    }
}

/// A `List` on the Busnes background with Busnes row surfaces. A row's own `listRowBackground` wins.
struct BusnesList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List { Group { content }.listRowBackground(Color.busnesSurface) }
            .scrollContentBackground(.hidden)
            .background(Color.busnesBackground)
    }
}
