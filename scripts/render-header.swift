// App Store Creative Assets, no alpha:
// - product page header, 3840 x 1646 px: icon, name and tagline centred in Apple's 1646 x 661 safe
//   area; the phones sit outside it as supporting imagery that narrow devices may crop.
// - search results artwork, 3840 x 2560 px (3:2): title on the left and two phones on the right of
//   Apple's centred 2168 x 1030 safe area. It stands in for the screenshots in search results.
//
// Usage: swift scripts/render-header.swift   (run from the repo root after capture-screenshots.sh)
// Writes Distribution/Promo/{header,search}-{light,dark}.png.

import AppKit

let tagline = "Sign-in codes and approvals that stay on your device."

struct Palette {
    let name: String
    let background, text, secondary, accent: NSColor
}

func hex(_ value: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(value >> 16 & 0xff) / 255, green: CGFloat(value >> 8 & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255, alpha: 1)
}

let palettes = [
    Palette(name: "light", background: hex(0xf8f6f0), text: hex(0x182326), secondary: hex(0x5b6669), accent: hex(0xbf3f18)),
    Palette(name: "dark", background: hex(0x182326), text: hex(0xf8f6f0), secondary: hex(0xb4bcbe), accent: hex(0xf5865f)),
]
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func image(_ path: String) -> NSImage {
    guard let image = NSImage(contentsOfFile: path) else { fatalError("missing \(path); run capture-screenshots.sh first") }
    return image
}

func screenshot(_ name: String, _ palette: Palette) -> NSImage {
    image("Distribution/Screenshots/iPhone-6.3/\(name)-\(palette.name).png")
}

/// A canvas of `size` pixels, y running down, filled with the palette background.
func canvas(_ size: CGSize, _ palette: Palette) -> CGContext {
    guard let cg = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                             space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fatalError("no bitmap context") }
    cg.translateBy(x: 0, y: size.height)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    cg.setFillColor(palette.background.cgColor)
    cg.fill(CGRect(origin: .zero, size: size))
    return cg
}

func save(_ cg: CGContext, _ path: String) {
    NSGraphicsContext.current = nil
    guard let output = cg.makeImage(),
          let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
    else { fatalError("could not write \(path)") }
    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(path)") }
    print(path)
}

/// A soft accent glow that ties the phones to the palette.
func glow(at center: CGPoint, radius: CGFloat, _ palette: Palette, in cg: CGContext) {
    let gradient = CGGradient(colorsSpace: space, colors: [palette.accent.withAlphaComponent(0.14).cgColor,
                                                           palette.accent.withAlphaComponent(0).cgColor] as CFArray,
                              locations: [0, 1])!
    cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// A phone: the screenshot with rounded screen corners inside a charcoal bezel, tilted about its centre.
func drawPhone(_ shot: NSImage, center: CGPoint, height phoneHeight: CGFloat, degrees: CGFloat, in cg: CGContext) {
    let screen = CGSize(width: phoneHeight * 1206 / 2622, height: phoneHeight)
    let bezel = phoneHeight * 0.02
    let screenRadius = phoneHeight * 0.064
    cg.saveGState()
    cg.translateBy(x: center.x, y: center.y)
    cg.rotate(by: degrees * .pi / 180)
    let body = CGRect(x: -screen.width / 2 - bezel, y: -screen.height / 2 - bezel,
                      width: screen.width + 2 * bezel, height: screen.height + 2 * bezel)
    cg.setShadow(offset: CGSize(width: 0, height: phoneHeight * 0.03), blur: phoneHeight * 0.06,
                 color: NSColor(white: 0, alpha: 0.26).cgColor)
    cg.addPath(CGPath(roundedRect: body, cornerWidth: screenRadius + bezel, cornerHeight: screenRadius + bezel, transform: nil))
    cg.setFillColor(hex(0x0e1517).cgColor)
    cg.fillPath()
    cg.setShadow(offset: .zero, blur: 0, color: nil)
    let screenRect = CGRect(x: -screen.width / 2, y: -screen.height / 2, width: screen.width, height: screen.height)
    cg.addPath(CGPath(roundedRect: screenRect, cornerWidth: screenRadius, cornerHeight: screenRadius, transform: nil))
    cg.clip()
    shot.draw(in: screenRect)
    cg.restoreGState()
}

/// Icon, "KyAuth" and the tagline stacked inside `box`, centred or left-aligned, at `scale`
/// (1 = 250 px icon). The tagline shrinks until it fits the box.
func drawTitle(in box: CGRect, centred: Bool, scale: CGFloat, _ palette: Palette, in cg: CGContext) {
    let iconSize = 250 * scale
    var taglineSize = 64 * scale
    var taglineAttributes: [NSAttributedString.Key: Any]
    repeat {
        taglineAttributes = [.font: NSFont.systemFont(ofSize: taglineSize, weight: .medium), .foregroundColor: palette.secondary]
        taglineSize -= 1
    } while (tagline as NSString).size(withAttributes: taglineAttributes).width > box.width
    let name = NSAttributedString(string: "KyAuth", attributes: [
        .font: NSFont.systemFont(ofSize: 170 * scale, weight: .bold), .foregroundColor: palette.text, .kern: -2 * scale,
    ])
    let line = NSAttributedString(string: tagline, attributes: taglineAttributes)
    let gap = 36 * scale
    let total = iconSize + gap + name.size().height + 8 * scale + line.size().height
    var y = box.midY - total / 2
    func x(_ width: CGFloat) -> CGFloat { centred ? box.midX - width / 2 : box.minX }

    let iconRect = CGRect(x: x(iconSize), y: y, width: iconSize, height: iconSize)
    let iconPath = CGPath(roundedRect: iconRect, cornerWidth: iconSize * 0.2237, cornerHeight: iconSize * 0.2237, transform: nil)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: 18 * scale), blur: 40 * scale, color: NSColor(white: 0, alpha: 0.22).cgColor)
    cg.addPath(iconPath)
    cg.setFillColor(palette.background.cgColor)
    cg.fillPath()
    cg.restoreGState()
    cg.saveGState()
    cg.addPath(iconPath)
    cg.clip()
    image("KyAuth/Assets.xcassets/AppIcon.appiconset/AppIcon.png").draw(in: iconRect)
    cg.restoreGState()
    // The icon's charcoal would vanish into the dark background without an edge.
    cg.addPath(CGPath(roundedRect: iconRect.insetBy(dx: 2, dy: 2), cornerWidth: iconSize * 0.2237, cornerHeight: iconSize * 0.2237, transform: nil))
    cg.setStrokeColor(palette.text.withAlphaComponent(0.14).cgColor)
    cg.setLineWidth(4 * scale)
    cg.strokePath()
    y += iconSize + gap

    name.draw(at: CGPoint(x: x(name.size().width), y: y))
    y += name.size().height + 8 * scale
    line.draw(at: CGPoint(x: x(line.size().width), y: y))
}

/// Centred safe area of `size` inside a canvas of `canvas`.
func safeArea(_ size: CGSize, in canvas: CGSize) -> CGRect {
    CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height)
}

func renderHeader(_ palette: Palette) {
    let size = CGSize(width: 3840, height: 1646)
    let safe = safeArea(CGSize(width: 1646, height: 661), in: size)
    let cg = canvas(size, palette)
    for x in [640.0, 3200.0] { glow(at: CGPoint(x: x, y: 823), radius: 620, palette, in: cg) }
    drawPhone(screenshot("01-codes", palette), center: CGPoint(x: 640, y: 830), height: 1080, degrees: -6, in: cg)
    drawPhone(screenshot("02-request", palette), center: CGPoint(x: 3200, y: 830), height: 1080, degrees: 6, in: cg)
    drawTitle(in: safe.insetBy(dx: 160, dy: 40), centred: true, scale: 0.74, palette, in: cg)
    save(cg, "Distribution/Promo/header-\(palette.name).png")
}

func renderSearch(_ palette: Palette) {
    let size = CGSize(width: 3840, height: 2560)
    let safe = safeArea(CGSize(width: 2168, height: 1030), in: size)
    let cg = canvas(size, palette)
    glow(at: CGPoint(x: safe.midX + 520, y: size.height / 2), radius: 1100, palette, in: cg)
    let title = CGRect(x: safe.minX, y: safe.minY, width: safe.width * 0.48, height: safe.height)
    drawTitle(in: title, centred: false, scale: 0.9, palette, in: cg)
    drawPhone(screenshot("01-codes", palette), center: CGPoint(x: safe.maxX - 640, y: size.height / 2 + 40),
              height: 1300, degrees: -5, in: cg)
    drawPhone(screenshot("02-request", palette), center: CGPoint(x: safe.maxX - 230, y: size.height / 2 - 20),
              height: 1360, degrees: 5, in: cg)
    save(cg, "Distribution/Promo/search-\(palette.name).png")
}

try FileManager.default.createDirectory(atPath: "Distribution/Promo", withIntermediateDirectories: true)
for palette in palettes {
    renderHeader(palette)
    renderSearch(palette)
}
