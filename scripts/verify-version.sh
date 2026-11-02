#!/usr/bin/env bash
#
# Keeps the places a version is written from drifting apart, and checks the
# tag on a release build.
#
#   MARKETING_VERSION        project.pbxproj, once per target and build
#                            configuration, and nothing makes them agree
#   CURRENT_PROJECT_VERSION  the same; release.yml uploads exactly this build
#                            number, so drift here is as bad as in the version
#   git tag                  v<x.y.z> -- what the release is named
#
# CFBundleShortVersionString is what App Store Connect files a build under,
# and it cannot be corrected after upload. Xcode edits one configuration at a
# time, so the copies drift silently: bumping the app's Release and forgetting
# the extension's produces an upload App Store Connect refuses, or worse,
# accepts.
#
# Prints `MARKETING_VERSION = x` and `CURRENT_PROJECT_VERSION = n`;
# scripts/verify-archive.sh reads both lines.
#
# Usage: verify-version.sh [tag]
#   tag defaults to $GITHUB_REF_NAME when the ref is a tag, else no tag check.

set -euo pipefail

cd "$(dirname "$0")/.."

pbxproj=KyAuth.xcodeproj/project.pbxproj
[ -f "$pbxproj" ] || { echo "no $pbxproj here" >&2; exit 1; }

# One distinct value of a build setting across the file. More than one is
# drift; none at all means the setting was renamed or removed and this check
# has quietly stopped checking anything. No mapfile: macOS's /bin/bash is 3.2.
single_setting() {
  local values count
  values=$(sed -n "s/^[[:space:]]*$1 = \\([^;]*\\);.*/\\1/p" "$pbxproj" | sort -u)
  count=$(printf '%s' "$values" | grep -c . || true)
  if [ "$count" -eq 0 ]; then
    echo "no $1 in $pbxproj -- this check is not checking anything" >&2
    return 1
  fi
  if [ "$count" -gt 1 ]; then
    echo "drift inside $pbxproj: $1 is set to $count different values:" >&2
    printf '%s\n' "$values" | sed 's/^/  /' >&2
    return 1
  fi
  printf '%s' "$values"
}

version=$(single_setting MARKETING_VERSION)
build=$(single_setting CURRENT_PROJECT_VERSION)
echo "MARKETING_VERSION = ${version}"
echo "CURRENT_PROJECT_VERSION = ${build}"

tag="${1-}"
if [ -z "$tag" ] && [ "${GITHUB_REF_TYPE-}" = "tag" ]; then
  tag="${GITHUB_REF_NAME-}"
fi
[ -n "$tag" ] || exit 0

# Tags are `v0.6.0`; the build setting is bare. Compared with the prefix
# stripped so the two conventions can coexist.
if [ "${tag#v}" != "$version" ]; then
  echo "tag ${tag} does not match MARKETING_VERSION ${version}" >&2
  exit 1
fi
echo "tag ${tag} matches"
