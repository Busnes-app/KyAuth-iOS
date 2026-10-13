#!/usr/bin/env bash
#
# App Store screenshots from the review demo (KyAuth/App/DemoMode.swift), driven by
# KyAuthUITests/ScreenshotTests. Nothing here pairs, unlocks a vault or touches the network.
#
# Usage: scripts/capture-screenshots.sh [iphone|ipad|duo|all] [output-dir]
#   output-dir defaults to ./Distribution/Screenshots; iphone writes <output-dir>/iPhone-6.3
#   (the required iPhone size, 1206 x 2622), ipad <output-dir>/iPad-13 (required for an app that
#   runs on iPad, 2064 x 2752), duo <output-dir>/iPhone-Duo-outer (1398 x 2034) and
#   iPhone-Duo-inner (2007 x 2853; required from April 2027 for apps built with the iOS 27.1 SDK).
#
# The Duo simulator boots folded and nothing on the command line unfolds it, so the inner display
# is captured only if it was unfolded by hand in Xcode's DeviceHub first. A display whose images
# are all identical was off, and is dropped with a message.
#
# Images come from the test result bundle, so no screen-recording permission is needed.

set -euo pipefail

cd "$(dirname "$0")/.."

target="${1:-all}"
outdir="${2:-Distribution/Screenshots}"
work="${TMPDIR:-/tmp}/kyauth-screenshots"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# xcodebuild passes TEST_RUNNER_-prefixed variables into the test runner with the prefix
# stripped; a plain KYAUTH_SCREENSHOTS=1 argument would only set a build setting.
export TEST_RUNNER_KYAUTH_SCREENSHOTS=1

# Each capture runs on its own throwaway simulator: other sessions may be driving the named ones,
# and a new device is the fresh install Try Demo needs (unpaired, no vault).
# Newest iOS runtime that supports the device type: iOS 27.1 is the iPhone Duo's alone.
runtime() {
    xcrun simctl list runtimes available --json | /usr/bin/python3 -c '
import json, sys
kind = "com.apple.CoreSimulator.SimDeviceType." + sys.argv[1]
ios = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS"
       and any(t["identifier"] == kind for t in r["supportedDeviceTypes"])]
print(max(ios, key=lambda r: [int(p) for p in r["version"].split(".")])["identifier"] if ios else "")
' "$1"
}

created=()
cleanup() {
    for udid in "${created[@]}"; do
        xcrun simctl shutdown "$udid" 2>/dev/null || true
        xcrun simctl delete "$udid" 2>/dev/null || true
    done
}
trap cleanup EXIT

# Boots a new simulator of the given device type at 9:41 with a full battery; prints its UDID.
new_device() {
    local udid
    local os
    os="$(runtime "$1")"
    [[ -n "$os" ]] || { echo "no installed iOS runtime supports $1" >&2; exit 1; }
    udid="$(xcrun simctl create "KyAuth screenshots" "com.apple.CoreSimulator.SimDeviceType.$1" "$os")"
    created+=("$udid")
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" >/dev/null
    xcrun simctl status_bar "$udid" override --time "9:41" --batteryState discharging \
        --batteryLevel 100 --cellularBars 4 --wifiBars 3
    echo "$udid"
}

# Copies the PNG attachments out under their test names (01-codes-light.png, ...). A Duo attaches
# one image per display, suffixed with its pixel size; those go to iPhone-Duo-outer/-inner.
export_shots() {
    local result="$1" dest="$2" staging
    staging="$(mktemp -d)"
    xcrun xcresulttool export attachments --path "$result" --output-path "$staging" >/dev/null
    mkdir -p "$dest"
    /usr/bin/python3 - "$staging" "$dest" <<'PY'
import json, os, re, shutil, sys

import hashlib, subprocess

staging, dest = sys.argv[1], sys.argv[2]
# XCUIScreen gives the inner display one pixel short of App Store Connect's size; padding the
# bottom-right edge by one pixel adds no visible content.
duo = {"1398x2034": ("iPhone-Duo-outer", None), "2006x2852": ("iPhone-Duo-inner", (2853, 2007)),
       "2007x2853": ("iPhone-Duo-inner", None)}

def walk(node):
    if isinstance(node, dict):
        if "exportedFileName" in node and "suggestedHumanReadableName" in node:
            yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value)

shots = {}  # display ("" for single-screen devices) -> [(name, source path)]
for item in walk(json.load(open(os.path.join(staging, "manifest.json")))):
    match = re.fullmatch(r"(\d\d-[a-z]+-(?:light|dark))(?:-(\d+x\d+))?_\d+_[0-9A-F-]{36}\.png",
                         item["suggestedHumanReadableName"])
    if match:
        shots.setdefault(match[2] or "", []).append((match[1], os.path.join(staging, item["exportedFileName"])))

count = 0
for display, files in sorted(shots.items()):
    folder, pad = duo.get(display, ("", None)) if display else ("", None)
    if display and not folder:
        sys.exit(f"unexpected display size {display}")
    if display and len({hashlib.sha256(open(f, "rb").read()).digest() for _, f in files}) == 1:
        print(f"    {folder}: skipped, the display was off (unfold the Duo in DeviceHub to capture it)")
        continue
    out = os.path.join(dest, folder) if folder else dest
    os.makedirs(out, exist_ok=True)
    for name, source in sorted(files):
        target = os.path.join(out, name + ".png")
        shutil.copy(source, target)
        if pad:
            subprocess.run(["sips", "--padToHeightWidth", str(pad[0]), str(pad[1]), target],
                           check=True, stdout=subprocess.DEVNULL)
        print("   ", os.path.relpath(target, dest))
        count += 1
if count == 0:
    sys.exit("no screenshots in the result bundle")
PY
    rm -rf "$staging"
}

capture() {
    local label="$1" dest="$2" type="$3"
    local udid
    # Not `udid="$(new_device ...)"`: a subshell could not record the device for cleanup.
    new_device "$type" >"$work/$label.udid"
    udid="$(tail -1 "$work/$label.udid")"
    local result="$work/$label.xcresult"
    rm -rf "$result"
    echo "==> $label"
    xcodebuild test -project KyAuth.xcodeproj -scheme KyAuth \
        -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$work/dd" \
        -only-testing:KyAuthUITests/ScreenshotTests -resultBundlePath "$result" \
        CODE_SIGNING_ALLOWED=NO >"$work/$label.log" 2>&1 \
        || { tail -30 "$work/$label.log"; exit 1; }
    export_shots "$result" "$dest"
}

mkdir -p "$work"
case "$target" in
    iphone|ipad|duo|all) ;;
    *) echo "usage: $0 [iphone|ipad|duo|all] [output-dir]" >&2; exit 2 ;;
esac
if [[ "$target" == iphone || "$target" == all ]]; then
    capture iphone "$outdir/iPhone-6.3" iPhone-18-Pro
fi
if [[ "$target" == ipad || "$target" == all ]]; then
    capture ipad "$outdir/iPad-13" iPad-Pro-13-inch-M5-12GB
fi
if [[ "$target" == duo || "$target" == all ]]; then
    capture duo "$outdir" iPhone-Duo
fi
echo "==> written to $outdir"
