#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: scripts/test-ios.sh DISPOSABLE_SIMULATOR_UUID" >&2
  exit 2
fi
fixture_simulator=$1
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
umask 077
mkdir -p .tls-fixtures/certificates

# The CI runner configures this reserved hostname; local users configure their
# own host once. Never modify a local machine's /etc/hosts from this script.
python3 - <<'PY'
import socket
if socket.gethostbyname("kyauth-tls-test.invalid") != "127.0.0.1":
    raise SystemExit("Map kyauth-tls-test.invalid to 127.0.0.1 before native TLS tests.")
PY

go -C scripts/tls-fixtures build -o "$repo_root/.tls-fixtures/server" .
GODEBUG=fips140=off .tls-fixtures/server -certificates .tls-fixtures/certificates -generate
fixture_state=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
device = sys.argv[1]
print(next(d["state"] for group in json.load(sys.stdin)["devices"].values() for d in group if d["udid"] == device))
' "$fixture_simulator")
if [ "$fixture_state" != Booted ]; then
  xcrun simctl boot "$fixture_simulator"
fi
xcrun simctl bootstatus "$fixture_simulator" -b
for fixture_anchor in .tls-fixtures/certificates/root.pem .tls-fixtures/certificates/anchor-*.pem; do
  xcrun simctl keychain "$fixture_simulator" add-root-cert "$fixture_anchor"
done

GODEBUG=fips140=off .tls-fixtures/server -certificates .tls-fixtures/certificates > .tls-fixtures/server.log 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || :; wait "$fixture_pid" 2>/dev/null || :' EXIT
fixture_ready=false
for _ in {1..30}; do
  if curl --silent --show-error --fail --noproxy kyauth-tls-test.invalid \
    --cacert .tls-fixtures/certificates/root.pem https://kyauth-tls-test.invalid:46100/health > /dev/null 2>&1; then
    fixture_ready=true
    break
  fi
  sleep 0.2
done
if [ "$fixture_ready" != true ]; then
  cat .tls-fixtures/server.log >&2
  echo "TLS fixture did not become ready" >&2
  exit 1
fi

fixture_results=$(mktemp -d "$repo_root/.tls-fixtures/results-XXXXXXXX")
fixture_test_status=0
xcodebuild -project KyAuth.xcodeproj -scheme KyAuth \
  -destination "platform=iOS Simulator,id=$fixture_simulator" \
  -resultBundlePath "$fixture_results/TestResults.xcresult" \
  -enableCodeCoverage YES CODE_SIGNING_ALLOWED=NO test || fixture_test_status=$?

# Xcode can retain Swift Testing stdout only in the result bundle. Keep a
# separate public counter snapshot in both the console and the artifact.
echo 'KYAUTH_TLS_FIXTURE_STATS (public fixture counters, after native tests)'
fixture_stats_status=0
curl --silent --show-error --fail --noproxy kyauth-tls-test.invalid \
  --cacert .tls-fixtures/certificates/root.pem https://kyauth-tls-test.invalid:46100/stats \
  | tee "$fixture_results/fixture-stats.json" || fixture_stats_status=$?
if [ "$fixture_stats_status" -ne 0 ]; then
  rm -f "$fixture_results/fixture-stats.json"
fi
# Preserve assertion messages and native error codes even when Xcode hides
# Swift Testing stdout. These contain only disposable fixture observations.
xcrun xcresulttool get test-results summary --path "$fixture_results/TestResults.xcresult" \
  > "$fixture_results/test-summary.json" || :
if [ -s "$fixture_results/test-summary.json" ]; then
  cat "$fixture_results/test-summary.json"
fi
# Which lines the suite executed. This is execution measurement,
# not branch, input or functionality coverage, so no assurance answer rests on
# it alone. A successful run must produce a report with per-target data.
fixture_coverage_status=0
xcrun xccov view --report --json "$fixture_results/TestResults.xcresult" \
  > "$fixture_results/coverage.json" || fixture_coverage_status=$?
if [ "$fixture_coverage_status" -eq 0 ]; then
  python3 - "$fixture_results/coverage.json" <<'PY' || fixture_coverage_status=$?
import json, sys
try:
    with open(sys.argv[1]) as source:
        loaded = json.load(source)
    reports = loaded if isinstance(loaded, list) else [loaded]
    targets = []
    for report in reports:
        if not isinstance(report, dict) or not isinstance(report.get("targets"), list):
            raise ValueError("expected xccov reports with target arrays")
        targets.extend(report["targets"])
    for name in ("KyAuth.app", "KyAuthPush.appex"):
        matches = [target for target in targets if target["name"] == name]
        if name == "KyAuthPush.appex" and not matches:
            print("KYAUTH_UNMEASURED_TARGET " + name)
            continue
        if len(matches) != 1:
            raise ValueError("expected exactly one coverage target: " + name)
        target = matches[0]
        covered, executable = target["coveredLines"], target["executableLines"]
        if type(covered) is not int or type(executable) is not int or not 0 <= covered <= executable or (name == "KyAuth.app" and executable == 0):
            raise ValueError("invalid " + name + " line counts")
        if name == "KyAuthPush.appex" and executable == 0:
            print("KYAUTH_UNMEASURED_TARGET " + name)
        elif name == "KyAuthPush.appex" and covered == 0:
            print("KYAUTH_UNEXERCISED_TARGET %s %d/%d" % (name, covered, executable))
        else:
            print("KYAUTH_TARGET_LINE_COVERAGE %s %d/%d" % (name, covered, executable))
except (OSError, ValueError, KeyError, TypeError) as error:
    raise SystemExit("Unusable xccov report: " + str(error)) from error
PY
fi
if [ "$fixture_coverage_status" -ne 0 ]; then
  rm -f "$fixture_results/coverage.json"
  echo "no usable xccov coverage report in $fixture_results" >&2
fi
if [ "$fixture_test_status" -ne 0 ]; then
  if [ -f "$fixture_results/coverage.json" ]; then
    mv "$fixture_results/coverage.json" "$fixture_results/coverage-from-failed-tests.json"
  fi
  exit "$fixture_test_status"
fi
if [ "$fixture_stats_status" -ne 0 ] || [ "$fixture_coverage_status" -ne 0 ]; then
  if [ -f "$fixture_results/coverage.json" ]; then
    mv "$fixture_results/coverage.json" "$fixture_results/coverage-from-incomplete-run.json"
  fi
  exit 1
fi
