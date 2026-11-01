import Foundation
import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import KyAuth

/// ky-ui's status colour gate (`scripts/check-status-colours.mjs`) on every color set this app
/// ships, light and dark: status text at 4.5:1 on background, surface and its own soft tint,
/// CIEDE2000 at least 20 between accent and danger and 10 between any two of accent, danger,
/// warning and success. Also each soft tint is ky-ui's 12% mix over the surface, and button text
/// reads on the accent. `scripts/theme-colorsets.py --check` runs the same gate on the JSON.
struct ThemeColourTests {
    typealias RGB = [Double] // 0...255 per channel

    static let halves: [(ThemePair, Bool)] = ThemePair.allCases.flatMap { [($0, false), ($0, true)] }

    @Test(arguments: ThemeColourTests.halves)
    func statusColoursPassTheGate(pair: ThemePair, dark: Bool) throws {
        let c = try Dictionary(uniqueKeysWithValues: ThemeRole.allCases.map { ($0, try Self.color(pair, $0, dark: dark)) })
        let half = "\(pair.title) \(dark ? "dark" : "light")"
        for (status, soft) in [(ThemeRole.danger, ThemeRole.dangerSoft), (.warning, .warningSoft), (.success, .successSoft)] {
            for ground in [ThemeRole.background, .surface, soft] {
                let ratio = Self.contrast(c[status]!, c[ground]!)
                #expect(ratio >= 4.5, "\(half): \(status) on \(ground) is \(ratio)")
            }
            let mixed = Self.mix(c[status]!, 12, c[.surface]!)
            #expect(zip(mixed, c[soft]!).allSatisfy { abs($0 - $1) <= 1 }, "\(half): \(soft) is not 12% \(status) over surface")
        }
        let accentDanger = Self.deltaE(c[.accent]!, c[.danger]!)
        #expect(accentDanger >= 20, "\(half): ΔE accent–danger \(accentDanger)")
        for (a, b) in [(ThemeRole.accent, ThemeRole.warning), (.accent, .success), (.danger, .warning), (.danger, .success), (.warning, .success)] {
            let distance = Self.deltaE(c[a]!, c[b]!)
            #expect(distance >= 10, "\(half): ΔE \(a)–\(b) \(distance)")
        }
        let button = Self.contrast(c[.onAccent]!, c[.accent]!)
        #expect(button >= 4.5, "\(half): onAccent on accent \(button)")
    }

    @Test func dangerIsNeverTheBusnesAccent() throws {
        for dark in [false, true] {
            #expect(try Self.color(.busnes, .danger, dark: dark) != Self.color(.busnes, .accent, dark: dark))
        }
    }

    @Test func gateMathMatchesKnownValues() {
        #expect(abs(Self.contrast([0, 0, 0], [255, 255, 255]) - 21) < 0.001)
        // Sharma, Wu and Dalal (2005), table 1, pair 1.
        #expect(abs(Self.ciede2000((50, 2.6772, -79.7751), (50, 0, -82.7485)) - 2.0425) < 0.0001)
        #expect(Self.mix([255, 0, 0], 12, [255, 255, 255]) == [255, 224, 224])
    }

    // MARK: - Colors

    /// The compiled asset catalog where UIKit exists; elsewhere the color set JSON in the source tree.
    static func color(_ pair: ThemePair, _ role: ThemeRole, dark: Bool) throws -> RGB {
        #if canImport(UIKit)
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let color = try #require(UIColor(named: pair.assetName(role), in: .main, compatibleWith: traits))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a))
        return [r, g, b].map { (Double($0) * 255).rounded() }
        #else
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KyAuth/Assets.xcassets/\(pair.assetName(role)).colorset/Contents.json")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let colors = try #require(json["colors"] as? [[String: Any]])
        let entry = try #require(colors.first { ($0["appearances"] != nil) == dark })
        let components = try #require((entry["color"] as? [String: Any])?["components"] as? [String: String])
        return try ["red", "green", "blue"].map { Double(try #require(UInt8(components[$0]!.dropFirst(2), radix: 16))) }
        #endif
    }

    // MARK: - ky-ui's gate, ported

    static func linear(_ v: Double) -> Double {
        let v = v / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func luminance(_ c: RGB) -> Double {
        zip(c.map(linear), [0.2126, 0.7152, 0.0722]).map(*).reduce(0, +)
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// CSS `color-mix(in srgb, a p%, b)`: per channel, on the encoded values.
    static func mix(_ a: RGB, _ percent: Double, _ b: RGB) -> RGB {
        zip(a, b).map { ($0 * percent / 100 + $1 * (1 - percent / 100)).rounded() }
    }

    static func lab(_ c: RGB) -> (Double, Double, Double) {
        let (r, g, b) = (linear(c[0]), linear(c[1]), linear(c[2]))
        let x: Double = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y: Double = 0.2126729 * r + 0.7151522 * g + 0.072175 * b
        let z: Double = (0.0193339 * r + 0.119192 * g + 0.9503041 * b) / 1.08883
        let xyz = [x, y, z].map { (t: Double) -> Double in t > 216 / 24389 ? cbrt(t) : (24389 / 27 * t + 16) / 116 }
        return (116 * xyz[1] - 16, 500 * (xyz[0] - xyz[1]), 200 * (xyz[1] - xyz[2]))
    }

    static func deltaE(_ a: RGB, _ b: RGB) -> Double { ciede2000(lab(a), lab(b)) }

    /// Sharma, Wu and Dalal (2005), kL = kC = kH = 1.
    static func ciede2000(_ lab1: (Double, Double, Double), _ lab2: (Double, Double, Double)) -> Double {
        let (L1, a1, b1) = lab1, (L2, a2, b2) = lab2
        let rad = Double.pi / 180
        let C = (hypot(a1, b1) + hypot(a2, b2)) / 2
        let G = 0.5 * (1 - sqrt(pow(C, 7) / (pow(C, 7) + pow(25, 7))))
        let (ap1, ap2) = (a1 * (1 + G), a2 * (1 + G))
        let (Cp1, Cp2) = (hypot(ap1, b1), hypot(ap2, b2))
        let hue = { (b: Double, a: Double) in (atan2(b, a) / rad + 360).truncatingRemainder(dividingBy: 360) }
        let (hp1, hp2) = (hue(b1, ap1), hue(b2, ap2))
        let dL = L2 - L1, dC = Cp2 - Cp1
        var dh = Cp1 * Cp2 == 0 ? 0 : hp2 - hp1
        if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
        let dH = 2 * sqrt(Cp1 * Cp2) * sin(dh * rad / 2)
        let Lm = (L1 + L2) / 2, Cm = (Cp1 + Cp2) / 2
        var hm = hp1 + hp2
        if Cp1 * Cp2 != 0 { hm = abs(hp1 - hp2) > 180 ? (hm + (hm < 360 ? 360 : -360)) / 2 : hm / 2 }
        let t1: Double = 1 - 0.17 * cos((hm - 30) * rad) + 0.24 * cos(2 * hm * rad)
        let T: Double = t1 + 0.32 * cos((3 * hm + 6) * rad) - 0.2 * cos((4 * hm - 63) * rad)
        let SL: Double = 1 + 0.015 * pow(Lm - 50, 2) / sqrt(20 + pow(Lm - 50, 2))
        let SC: Double = 1 + 0.045 * Cm, SH: Double = 1 + 0.015 * Cm * T
        let rotation: Double = 60 * exp(-pow((hm - 275) / 25, 2)) * rad
        let RT: Double = -2 * sqrt(pow(Cm, 7) / (pow(Cm, 7) + pow(25, 7))) * sin(rotation)
        let (l, c, h) = (dL / SL, dC / SC, dH / SH)
        return sqrt(l * l + c * c + h * h + RT * c * h)
    }
}
