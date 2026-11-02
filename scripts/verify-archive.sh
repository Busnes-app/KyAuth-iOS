#!/usr/bin/env bash
#
# Proves an archive carries the team, version and build number the project
# says it should, before release.yml uploads it. A swapped certificate secret
# produces a perfectly valid build signed by the wrong team, and App Store
# Connect files a build under whatever numbers it carries; neither can be
# walked back after upload.
#
# Checks KyAuth.app and every extension inside it (KyAuthPush must be there):
#   CFBundleShortVersionString and CFBundleVersion equal the project's single
#   MARKETING_VERSION and CURRENT_PROJECT_VERSION (scripts/verify-version.sh);
#   the code signature's TeamIdentifier equals the project's single
#   DEVELOPMENT_TEAM, which must also be the teamID the upload re-signs for in
#   Distribution/ExportOptions-iOS.plist.
# Numbers are checked before signatures, so an unsigned local archive still
# shows its numbers before the signer check refuses it.
#
# macOS only (PlistBuddy, codesign). Usage: verify-archive.sh ARCHIVE.xcarchive

set -euo pipefail

[ "$#" -eq 1 ] || { echo "usage: scripts/verify-archive.sh ARCHIVE.xcarchive" >&2; exit 2; }
archive=$(cd "$1" && pwd)
cd "$(dirname "$0")/.."

numbers=$(scripts/verify-version.sh)
version=$(printf '%s\n' "$numbers" | sed -n 's/^MARKETING_VERSION = //p')
build=$(printf '%s\n' "$numbers" | sed -n 's/^CURRENT_PROJECT_VERSION = //p')

pbxproj=KyAuth.xcodeproj/project.pbxproj
teams=$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM = \([^;]*\);.*/\1/p' "$pbxproj" | sort -u)
if [ "$(printf '%s' "$teams" | grep -c . || true)" -ne 1 ]; then
  echo "expected exactly one DEVELOPMENT_TEAM in $pbxproj, found: ${teams:-none}" >&2
  exit 1
fi
export_team=$(/usr/libexec/PlistBuddy -c 'Print :teamID' Distribution/ExportOptions-iOS.plist)
if [ "$export_team" != "$teams" ]; then
  echo "ExportOptions-iOS.plist uploads for team ${export_team}, the project builds for ${teams}" >&2
  exit 1
fi
echo "team ${teams}, version ${version}, build ${build}"

app="$archive/Products/Applications/KyAuth.app"
[ -d "$app" ] || { echo "no KyAuth.app in $archive" >&2; exit 1; }
[ -d "$app/PlugIns/KyAuthPush.appex" ] || { echo "no KyAuthPush.appex in $app" >&2; exit 1; }
bundles=("$app" "$app"/PlugIns/*.appex)

for bundle in "${bundles[@]}"; do
  name=$(basename "$bundle")
  actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Info.plist")
  actual_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bundle/Info.plist")
  if [ "$actual_version" != "$version" ] || [ "$actual_build" != "$build" ]; then
    echo "${name} is ${actual_version} (${actual_build}), expected ${version} (${build})" >&2
    exit 1
  fi
  echo "${name}: version ${actual_version}, build ${actual_build}"
done

for bundle in "${bundles[@]}"; do
  name=$(basename "$bundle")
  signer=$(codesign -dvv "$bundle" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)
  if [ "$signer" != "$teams" ]; then
    echo "${name} is signed by team '${signer:-none}', expected ${teams}" >&2
    exit 1
  fi
  echo "${name}: signer ${signer}"
done
