#!/usr/bin/env python3
"""Writes and checks the six suite theme pairs as asset catalog color sets.

Values are copied from ky-ui 0.11.0 (`src/themes.js` THEME_PALETTES and `src/tokens.css`); ky-ui
is the source of truth, so change a value there first. Each pair is `<Pair><Role>.colorset` with
a light and a dark appearance; Busnes keeps `AccentColor` as its accent, the app's global accent.
Soft tints are ky-ui's `color-mix(in srgb, <status> 12%, <panel>)`.

  python3 -I scripts/theme-colorsets.py --write          rewrite every color set
  python3 -I scripts/theme-colorsets.py --check          JSON matches this table, and ky-ui's status gate
  python3 -I scripts/theme-colorsets.py --sheet out.png  render every color set, light and dark (Pillow)

`KyAuthTests/ThemeTests.swift` runs the same gate against the compiled catalog.
"""
import json
import math
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "KyAuth" / "Assets.xcassets"

# Shared status defaults by scheme (tokens.css --ky-<status>-<scheme>).
STATUS = {
    "light": {"danger": "#a8174e", "warning": "#7a5f00", "success": "#267442"},
    "dark": {"danger": "#ff8fb1", "warning": "#ffd25e", "success": "#86efac"},
}
SOFT_PERCENT = 12

# background = bg, surface = panel, onAccent = buttonText; status keys override the defaults.
PAIRS = {
    "Busnes": {
        "light": {"background": "#f8f6f0", "surface": "#ffffff", "accent": "#bf3f18", "onAccent": "#ffffff"},
        "dark": {"background": "#182326", "surface": "#1f2b2e", "accent": "#f5865f", "onAccent": "#182326"},
    },
    "Matter": {
        "light": {"background": "#f5efe5", "surface": "#fff8ee", "accent": "#805a39", "onAccent": "#ffffff"},
        "dark": {"background": "#1d1b19", "surface": "#292725", "accent": "#c29a72", "onAccent": "#24170f"},
    },
    "Ocean": {
        "light": {"background": "#f7f9fb", "surface": "#ffffff", "accent": "#1d5fa6", "onAccent": "#ffffff"},
        "dark": {"background": "#0f1b24", "surface": "#152a36", "accent": "#6aa8e8", "onAccent": "#0a1b22"},
    },
    "Forest": {
        "light": {"background": "#f3f6ef", "surface": "#fcfdf9", "accent": "#4b6b37", "onAccent": "#ffffff", "success": "#00737a"},
        "dark": {"background": "#142018", "surface": "#1f2f24", "accent": "#8faa74", "onAccent": "#12200f", "success": "#6ee0d0"},
    },
    "Ky": {
        "light": {"background": "#eef2f6", "surface": "#ffffff", "accent": "#08758b", "onAccent": "#ffffff"},
        "dark": {"background": "#10161e", "surface": "#1b2530", "accent": "#6fc9cc", "onAccent": "#10161e"},
    },
    "Nord": {
        "light": {"background": "#eceff4", "surface": "#ffffff", "accent": "#4a6a94", "onAccent": "#ffffff"},
        "dark": {"background": "#2e3440", "surface": "#3b4252", "accent": "#88c0d0", "onAccent": "#0d0f14", "danger": "#ecc4c8", "success": "#bcd4aa"},
    },
}
ROLES = ["Background", "Surface", "Accent", "OnAccent", "Danger", "Warning", "Success", "DangerSoft", "WarningSoft", "SuccessSoft"]
STATUSES = ["danger", "warning", "success"]


def rgb(hex_):
    return [int(hex_[i:i + 2], 16) for i in (1, 3, 5)]


def mix(a, percent, b):
    return "#" + "".join(f"{round(x * percent / 100 + y * (1 - percent / 100)):02x}" for x, y in zip(rgb(a), rgb(b)))


def half(pair, scheme):
    values = dict(STATUS[scheme], **PAIRS[pair][scheme])
    for status in STATUSES:
        values[status + "Soft"] = mix(values[status], SOFT_PERCENT, values["surface"])
    return values


def asset_name(pair, role):
    return "AccentColor" if (pair, role) == ("Busnes", "Accent") else pair + role


def key(role):
    return role[0].lower() + role[1:]


def component(hex_):
    r, g, b = rgb(hex_)
    return f'{{ "alpha" : "1.000", "blue" : "0x{b:02X}", "green" : "0x{g:02X}", "red" : "0x{r:02X}" }}'


def colorset(light, dark):
    # Xcode's own layout, so the existing Busnes files stay byte-identical.
    return (
        '{\n  "colors" : [\n    {\n'
        f'      "color" : {{ "color-space" : "srgb", "components" : {component(light)} }},\n'
        '      "idiom" : "universal"\n    },\n    {\n'
        '      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],\n'
        f'      "color" : {{ "color-space" : "srgb", "components" : {component(dark)} }},\n'
        '      "idiom" : "universal"\n    }\n  ],\n'
        '  "info" : { "author" : "xcode", "version" : 1 }\n}\n'
    )


def expected():
    return {asset_name(p, r): colorset(half(p, "light")[key(r)], half(p, "dark")[key(r)]) for p in PAIRS for r in ROLES}


def read_colorset(name):
    data = json.loads((CATALOG / f"{name}.colorset" / "Contents.json").read_text())
    out = {}
    for entry in data["colors"]:
        scheme = "dark" if entry.get("appearances") else "light"
        c = entry["color"]["components"]
        out[scheme] = "#" + "".join(f"{int(c[k], 16):02x}" for k in ("red", "green", "blue"))
    return out


# --- ky-ui scripts/check-status-colours.mjs, ported -------------------------------------------

def linear(v):
    v /= 255
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def luminance(hex_):
    return sum(linear(v) * w for v, w in zip(rgb(hex_), (0.2126, 0.7152, 0.0722)))


def contrast(a, b):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def lab(hex_):
    r, g, b = (linear(v) for v in rgb(hex_))
    xyz = [
        (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047,
        0.2126729 * r + 0.7151522 * g + 0.072175 * b,
        (0.0193339 * r + 0.119192 * g + 0.9503041 * b) / 1.08883,
    ]
    f = [t ** (1 / 3) if t > 216 / 24389 else (24389 / 27 * t + 16) / 116 for t in xyz]
    return 116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2])


def ciede2000(lab1, lab2):
    (L1, a1, b1), (L2, a2, b2) = lab1, lab2
    rad = math.pi / 180
    C = (math.hypot(a1, b1) + math.hypot(a2, b2)) / 2
    G = 0.5 * (1 - math.sqrt(C ** 7 / (C ** 7 + 25 ** 7)))
    ap1, ap2 = a1 * (1 + G), a2 * (1 + G)
    Cp1, Cp2 = math.hypot(ap1, b1), math.hypot(ap2, b2)
    hp1, hp2 = (math.atan2(b1, ap1) / rad + 360) % 360, (math.atan2(b2, ap2) / rad + 360) % 360
    dL, dC = L2 - L1, Cp2 - Cp1
    dh = 0 if Cp1 * Cp2 == 0 else hp2 - hp1
    if dh > 180:
        dh -= 360
    elif dh < -180:
        dh += 360
    dH = 2 * math.sqrt(Cp1 * Cp2) * math.sin(dh * rad / 2)
    Lm, Cm = (L1 + L2) / 2, (Cp1 + Cp2) / 2
    hm = hp1 + hp2
    if Cp1 * Cp2 != 0:
        hm = (hm + (360 if hm < 360 else -360)) / 2 if abs(hp1 - hp2) > 180 else hm / 2
    T = 1 - 0.17 * math.cos((hm - 30) * rad) + 0.24 * math.cos(2 * hm * rad) + 0.32 * math.cos((3 * hm + 6) * rad) - 0.2 * math.cos((4 * hm - 63) * rad)
    SL = 1 + 0.015 * (Lm - 50) ** 2 / math.sqrt(20 + (Lm - 50) ** 2)
    SC, SH = 1 + 0.045 * Cm, 1 + 0.015 * Cm * T
    RT = -2 * math.sqrt(Cm ** 7 / (Cm ** 7 + 25 ** 7)) * math.sin(60 * math.exp(-(((hm - 275) / 25) ** 2)) * rad)
    return math.sqrt((dL / SL) ** 2 + (dC / SC) ** 2 + (dH / SH) ** 2 + RT * (dC / SC) * (dH / SH))


def delta_e(a, b):
    return ciede2000(lab(a), lab(b))


def gate(values):
    """ky-ui's checks for one half, plus button text on the accent. Returns (name, value, min)."""
    checks = []
    for s in STATUSES:
        checks += [
            (f"{s} on background", contrast(values[s], values["background"]), 4.5),
            (f"{s} on surface", contrast(values[s], values["surface"]), 4.5),
            (f"{s} on {s}Soft", contrast(values[s], values[s + "Soft"]), 4.5),
        ]
    checks.append(("ΔE accent–danger", delta_e(values["accent"], values["danger"]), 20))
    for a, b in [("accent", "warning"), ("accent", "success"), ("danger", "warning"), ("danger", "success"), ("warning", "success")]:
        checks.append((f"ΔE {a}–{b}", delta_e(values[a], values[b]), 10))
    checks.append(("onAccent on accent", contrast(values["onAccent"], values["accent"]), 4.5))
    return checks


def check():
    failures, count = [], 0
    for name, text in expected().items():
        count += 1
        path = CATALOG / f"{name}.colorset" / "Contents.json"
        if not path.exists() or path.read_text() != text:
            failures.append(f"{name}: color set differs from the table (run --write)")
    for pair in PAIRS:
        for scheme in ("light", "dark"):
            # The gate reads the written JSON, not the table, so it checks what ships.
            values = {key(r): read_colorset(asset_name(pair, r))[scheme] for r in ROLES}
            for label, value, minimum in gate(values):
                count += 1
                if not value >= minimum:
                    failures.append(f"{pair} {scheme}: {label} {value:.2f} < {minimum}")
    print("\n".join(failures) or f"theme colour sets: {count} checks pass ({len(expected())} color sets, {len(PAIRS) * 2} halves)")
    return 1 if failures else 0


def write():
    for name, text in expected().items():
        folder = CATALOG / f"{name}.colorset"
        folder.mkdir(exist_ok=True)
        (folder / "Contents.json").write_text(text)
    return 0


def sheet(out):
    from PIL import Image, ImageDraw, ImageFont

    import subprocess

    # Whatever sans fontconfig picks.
    face = lambda pattern: subprocess.run(["fc-match", "-f", "%{file}", pattern], capture_output=True, text=True, check=True).stdout
    regular_file, bold_file = face("sans"), face("sans:bold")
    font = lambda size: ImageFont.truetype(regular_file, size)
    bold = lambda size: ImageFont.truetype(bold_file, size)
    cell, pad, label_w = 112, 16, 150
    width = label_w + len(ROLES) * cell + pad * 2
    row_h = 210
    img = Image.new("RGB", (width, 90 + len(PAIRS) * 2 * row_h + 40), "#ffffff")
    d = ImageDraw.Draw(img)
    d.text((pad, 18), "KyAuth iOS: theme colour sets, rendered from Assets.xcassets JSON (not the app)", fill="#111111", font=bold(22))
    d.text((pad, 52), "Each row: swatches with asset name and hex; below, a sample row on Background/Surface with status labels.", fill="#444444", font=font(15))
    y = 90
    for pair in PAIRS:
        for scheme in ("light", "dark"):
            v = {key(r): read_colorset(asset_name(pair, r))[scheme] for r in ROLES}
            d.rectangle([0, y, width, y + row_h - 4], fill=v["background"])
            ink = "#000000" if scheme == "light" else "#ffffff"
            d.text((pad, y + 10), f"{pair}", fill=ink, font=bold(20))
            d.text((pad, y + 36), scheme.capitalize(), fill=ink, font=font(16))
            for i, role in enumerate(ROLES):
                x = label_w + i * cell
                d.rectangle([x, y + 10, x + cell - 10, y + 70], fill=v[key(role)], outline="#888888")
                d.text((x, y + 74), asset_name(pair, role), fill=ink, font=font(10))
                d.text((x, y + 88), v[key(role)], fill=ink, font=font(11))
            # Sample: a surface card with an accent button and the three statuses on their tints.
            cy = y + 112
            d.rounded_rectangle([pad, cy, width - pad, cy + 84], radius=12, fill=v["surface"])
            d.rounded_rectangle([pad + 14, cy + 22, pad + 134, cy + 62], radius=10, fill=v["accent"])
            d.text((pad + 40, cy + 31), "Approve", fill=v["onAccent"], font=bold(16))
            for i, (s, word, mark) in enumerate([("danger", "Error", "x"), ("warning", "Warning", "!"), ("success", "On", "v")]):
                x = pad + 160 + i * 230
                d.rounded_rectangle([x, cy + 22, x + 210, cy + 62], radius=10, fill=v[s + "Soft"])
                d.ellipse([x + 12, cy + 32, x + 32, cy + 52], fill=v[s])
                if mark == "!":
                    d.text((x + 19, cy + 33), "!", fill=v["surface"], font=bold(14))
                else:  # drawn, since not every sans has ✓ and ✕
                    lines = [[(x + 17, cy + 37), (x + 27, cy + 47)], [(x + 27, cy + 37), (x + 17, cy + 47)]] if mark == "x" \
                        else [[(x + 16, cy + 42), (x + 21, cy + 47), (x + 28, cy + 37)]]
                    for line in lines:
                        d.line(line, fill=v["surface"], width=3)
                d.text((x + 42, cy + 31), f"{word} {contrast(v[s], v[s + 'Soft']):.1f}:1", fill=v[s], font=bold(16))
            d.text((pad + 860, cy + 31), f"ΔE accent–danger {delta_e(v['accent'], v['danger']):.0f}", fill=ink, font=font(15))
            y += row_h
    img.save(out)
    return 0


if __name__ == "__main__":
    if sys.argv[1:2] == ["--write"]:
        sys.exit(write())
    if sys.argv[1:2] == ["--check"]:
        sys.exit(check())
    if sys.argv[1:2] == ["--sheet"] and len(sys.argv) == 3:
        sys.exit(sheet(sys.argv[2]))
    sys.exit(__doc__)
