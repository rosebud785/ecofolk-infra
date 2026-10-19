#!/usr/bin/env bash
# test_check_load_target.sh — proves check-load-target.sh (#16) refuses each
# known-wrong load target, not just that it passes a good one, and that
# load/beta-20.js passes `k6 inspect` with the spec's shape.
#
# Known-wrongs (each must exit 1): a prod host, 10.0.0.0/8, 172.16.0.0/12,
# 192.168.0.0/16, 127.0.0.0/8, and an http:// scheme. One good https control
# must exit 0. Hostnames are placeholders (example.com), never real ones.
#
# The k6 half runs the pinned image, never `latest`, so a k6 release can't
# change the verdict under us. It needs Docker; with no Docker it FAILS
# rather than skipping, because a skipped inspect proves nothing.
#
# Usage: bash scripts/tests/test_check_load_target.sh
# Exit: 0 if every case matches its expected outcome, 1 otherwise.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHK="$SCRIPT_DIR/../check-load-target.sh"
K6_IMAGE="grafana/k6:1.3.0"

pass=0; fail=0
check() {
  local name="$1" cond="$2"
  if eval "$cond"; then echo "PASS  $name"; pass=$((pass+1));
  else echo "FAIL  $name  (condition: $cond)"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. Known-wrongs: each must be refused, for the reason we expect.
refused() {
  local label="$1" url="$2" reason="$3" out rc
  out=$(bash "$CHK" "$url" 2>&1); rc=$?
  local said=0
  grep -q REFUSED <<< "$out" && grep -qF -- "$reason" <<< "$out" && said=1
  check "$label: exits 1" "[ $rc -eq 1 ]"
  check "$label: says REFUSED, $reason" "[ $said -eq 1 ]"
}
refused "prod host"      "https://api.prod.example.com/v1"  'contains "prod"'
refused "10.0.0.0/8"     "https://10.20.30.40/"             "10.0.0.0/8"
refused "172.16.0.0/12"  "https://172.20.1.2:8443/"         "172.16.0.0/12"
refused "192.168.0.0/16" "https://192.168.1.10/"            "192.168.0.0/16"
refused "127.0.0.0/8"    "https://127.0.0.1:8080/"          "127.0.0.0/8"
refused "http scheme"    "http://qa.example.com/"           "scheme is not https"

# 2. The one good control: a public https QA URL passes.
OUT_OK=$(bash "$CHK" "https://qa.example.com" 2>&1); RC_OK=$?
check "https control: exits 0" "[ $RC_OK -eq 0 ]"
OK_SAID=0; grep -q LOAD_TARGET_OK <<< "$OUT_OK" && OK_SAID=1
check "https control: says LOAD_TARGET_OK" "[ $OK_SAID -eq 1 ]"

# 3. k6 inspect on the real script, with the pinned image.
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  check "docker available for k6 inspect" "false"
else
  INSPECT=$(docker run --rm -v "$REPO_ROOT/load:/load:ro" "$K6_IMAGE" inspect /load/beta-20.js 2>&1); RC_I=$?
  check "k6 inspect load/beta-20.js: exits 0" "[ $RC_I -eq 0 ]"
  if [ "$RC_I" -eq 0 ]; then
    echo "$INSPECT" > "$WORK/inspect.json"
    check "k6 inspect: 20 VUs"            "[ \"\$(jq -r '.scenarios.beta_20.vus' '$WORK/inspect.json')\" = 20 ]"
    check "k6 inspect: 10 minutes"        "[ \"\$(jq -r '.scenarios.beta_20.duration' '$WORK/inspect.json')\" = 10m0s ]"
    check "k6 inspect: p95 < 800 ms"      "jq -e '.thresholds.http_req_duration | index(\"p(95)<800\")' '$WORK/inspect.json' >/dev/null"
    check "k6 inspect: errors < 1%"       "jq -e '.thresholds.http_req_failed | index(\"rate<0.01\")' '$WORK/inspect.json' >/dev/null"
  fi

  # 4. And k6 inspect can go red: a broken script must fail it.
  mkdir -p "$WORK/broken"
  echo 'export default function ( {' > "$WORK/broken/broken.js"
  docker run --rm -v "$WORK/broken:/load:ro" "$K6_IMAGE" inspect /load/broken.js >/dev/null 2>&1; RC_B=$?
  check "k6 inspect on a broken script: exits non-zero" "[ $RC_B -ne 0 ]"
fi

echo ""
echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
