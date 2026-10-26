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
xcrun simctl keychain "$fixture_simulator" add-root-cert .tls-fixtures/certificates/root.pem

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
xcodebuild -project KyAuth.xcodeproj -scheme KyAuth \
  -destination "platform=iOS Simulator,id=$fixture_simulator" \
  -resultBundlePath "$fixture_results/TestResults.xcresult" CODE_SIGNING_ALLOWED=NO test
