import SwiftUI
import UIKit

extension Appearance {
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

extension ThemeChoice {
    /// Set on the window rather than through `preferredColorScheme`, so sheets, alerts and
    /// confirmation dialogs follow it and returning to System takes effect at once. The window
    /// tint colors UIKit alerts; SwiftUI views take the accent from `.tint(.themeAccent)`.
    @MainActor func apply() {
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] {
                window.overrideUserInterfaceStyle = appearance.interfaceStyle
                window.tintColor = UIColor(named: pair.assetName(.accent))
            }
        }
    }
}

extension EnvironmentValues {
    private struct ThemePairKey: EnvironmentKey {
        static let defaultValue = ThemePair.busnes
    }

    /// Set once, on `RootView`, from the saved choice.
    var themePair: ThemePair {
        get { self[ThemePairKey.self] }
        set { self[ThemePairKey.self] = newValue }
    }
}

/// A theme color for the pair in the environment; the color set supplies the light or dark half.
struct ThemeColor: ShapeStyle {
    let role: ThemeRole

    func resolve(in environment: EnvironmentValues) -> Color {
        Color(environment.themePair.assetName(role))
    }
}

extension ShapeStyle where Self == ThemeColor {
    static var themeBackground: ThemeColor { ThemeColor(role: .background) }
    static var themeSurface: ThemeColor { ThemeColor(role: .surface) }
    static var themeAccent: ThemeColor { ThemeColor(role: .accent) }
    static var themeOnAccent: ThemeColor { ThemeColor(role: .onAccent) }
    static var themeDanger: ThemeColor { ThemeColor(role: .danger) }
    static var themeWarning: ThemeColor { ThemeColor(role: .warning) }
    static var themeSuccess: ThemeColor { ThemeColor(role: .success) }
    static var themeDangerSoft: ThemeColor { ThemeColor(role: .dangerSoft) }
    static var themeWarningSoft: ThemeColor { ThemeColor(role: .warningSoft) }
}

/// A `Form` on the theme background with theme row surfaces.
struct ThemedForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { Group { content }.listRowBackground(Rectangle().fill(.themeSurface)) }
            .scrollContentBackground(.hidden)
            .background(.themeBackground)
    }
}

/// A `List` on the theme background with theme row surfaces. A row's own `listRowBackground` wins.
struct ThemedList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List { Group { content }.listRowBackground(Rectangle().fill(.themeSurface)) }
            .scrollContentBackground(.hidden)
            .background(.themeBackground)
    }
}

extension View {
    /// A grouped-list section footer: footnote in the suite face. Without it the footer takes
    /// `RootView`'s body-size default.
    func sectionFooterStyle() -> some View {
        font(AppFont.ui(.footnote))
    }

    /// `.borderedProminent` with the theme's label color on its accent (dark text on dark-half
    /// accents, where white would fail contrast).
    func themedProminentButton() -> some View {
        buttonStyle(.borderedProminent).foregroundStyle(.themeOnAccent)
    }
}

extension Text {
    /// A grouped-list section header: footnote, semibold, ink at 60% (4.5:1 or better), in the case
    /// it is written in. iOS 26's default header is nearly body size and competes with its rows.
    func sectionHeaderStyle() -> some View {
        font(AppFont.ui(.footnote, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.6)).textCase(nil)
    }

    /// A text field placeholder in ink at 60%, at least 4.5:1 on every pair's surface; the
    /// system placeholder gray falls short of that.
    func placeholderStyle() -> Text {
        foregroundStyle(Color.primary.opacity(0.6))
    }
}

/// A state in words with its icon, in the status color: never color alone.
struct StatusLabel: View {
    enum Kind {
        case danger, warning, success

        var symbol: String {
            switch self {
            case .danger: "exclamationmark.octagon.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .success: "checkmark.circle.fill"
            }
        }

        var style: ThemeColor {
            switch self {
            case .danger: .themeDanger
            case .warning: .themeWarning
            case .success: .themeSuccess
            }
        }
    }

    let text: String
    let kind: Kind

    init(_ text: String, _ kind: Kind) {
        self.text = text
        self.kind = kind
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: kind.symbol)
        }
        .foregroundStyle(kind.style)
    }
}

/// Both halves of a pair: its background with an accent dot, light then dark.
struct ThemeSwatch: View {
    let pair: ThemePair

    var body: some View {
        HStack(spacing: 4) {
            half.environment(\.colorScheme, .light)
            half.environment(\.colorScheme, .dark)
        }
        .accessibilityHidden(true)
    }

    private var half: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(pair.assetName(.background)))
            .overlay(Circle().fill(Color(pair.assetName(.accent))).padding(7))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.quaternary))
            .frame(width: 28, height: 28)
    }
}
