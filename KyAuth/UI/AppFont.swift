import SwiftUI
import UIKit

/// Space Grotesk, the suite face (KyPost's `AppFont`). It ships in Resources/Fonts, registered
/// through `UIAppFonts`, so the family name always resolves. Only regular, medium, semibold and
/// bold are bundled and CoreText matches `.weight()` to those static faces: add the TTF before
/// using another weight. Sizes are the text style's default and follow Dynamic Type. The face has
/// tabular figures, so codes and countdowns keep `.monospacedDigit()`.
enum AppFont {
    static func ui(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .custom("Space Grotesk", size: size(style), relativeTo: style).weight(weight)
    }

    /// Navigation titles, bar buttons and tab labels are UIKit and ignore SwiftUI's `.font`.
    @MainActor static func applyToUIKit() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: uiFont("SpaceGrotesk-Bold", .largeTitle)]
        bar.titleTextAttributes = [.font: uiFont("SpaceGrotesk-SemiBold", .headline)]
        let button = [NSAttributedString.Key.font: uiFont("SpaceGrotesk-Regular", .body)]
        for state in [UIControl.State.normal, .highlighted, .disabled] {
            UIBarButtonItem.appearance().setTitleTextAttributes(button, for: state)
        }
        let tab = [NSAttributedString.Key.font: uiFont("SpaceGrotesk-Medium", .caption2, size: 10)]
        UITabBarItem.appearance().setTitleTextAttributes(tab, for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes(tab, for: .selected)
    }

    private static func uiFont(_ name: String, _ style: UIFont.TextStyle, size: CGFloat? = nil) -> UIFont {
        let base = size ?? UIFont.preferredFont(
            forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        ).pointSize
        let font = UIFont(name: name, size: base) ?? .systemFont(ofSize: base)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

    /// Each text style's size at the default content size (Apple's type ramp).
    private static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}
