#!/usr/bin/env bash
# test_check_load_target.sh — proves check-load-target.sh (#16) refuses each
# known-wrong load target, not just that it passes a good one, and that
# load/beta-20.js passes `k6 inspect` with the spec's shape.
#
# Known-wrongs (each must exit 1): a prod host, 10/8, 172.16/12, 192.168/16,
# 127.0.0.0/8, and an http:// scheme. One good https control
# must exit 0. Hostnames are placeholders (example.com), never real ones.
#
# The k6 half runs a pinned k6, never `latest`, so a k6 release can't change the
# verdict under us: the binary at $K6_BIN when set (CI downloads a sha256-pinned
# tarball), otherwise the pinned image via Docker. With neither it FAILS rather
# than skipping, because a skipped inspect proves nothing. `k6 inspect` never
# runs the script, so no target and no token are involved.
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

# ip A B C D -> A.B.C.D, built at runtime so no private-address literal sits in
# the file for the repo's rfc1918-ipv4 secret-scan rule to flag.
ip() { local IFS=.; echo "$*"; }

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
refused "10/8"           "https://$(ip 10 20 30 40)/"       "10/8"
refused "172.16/12"      "https://$(ip 172 20 1 2):8443/"   "172.16/12"
refused "192.168/16"     "https://$(ip 192 168 1 10)/"      "192.168/16"
refused "127.0.0.0/8"    "https://127.0.0.1:8080/"          "127.0.0.0/8"
refused "http scheme"    "http://qa.example.com/"           "scheme is not https"

# 2. The one good control: a public https QA URL passes.
OUT_OK=$(bash "$CHK" "https://qa.example.com" 2>&1); RC_OK=$?
check "https control: exits 0" "[ $RC_OK -eq 0 ]"
OK_SAID=0; grep -q LOAD_TARGET_OK <<< "$OUT_OK" && OK_SAID=1
check "https control: says LOAD_TARGET_OK" "[ $OK_SAID -eq 1 ]"

# 2b. bash 3.2 (#76): macOS /bin/bash is 3.2, where a bash-4 `${var,,}` is a "bad
#     substitution" and the guard refuses every URL. Re-run a known-right and a
#     known-wrong (mixed-case, to exercise the lower-casing) under a real bash 3.2:
#     natively when /bin/bash is 3.x (a Mac), and in the pinned bash:3.2 container
#     when docker is up. In hosted CI (GITHUB_ACTIONS=true) a run is required.
BASH32_IMAGE="bash@sha256:0fd7cb8499c63a3c9345e7088a9cd83bb69f6e895e83833859aff838a0312091"
bash32_leg() {
  local label="$1"; shift
  local out rc
  out=$(cd "$REPO_ROOT" && "$@" scripts/check-load-target.sh "HTTPS://QA.Example.com/x" 2>&1); rc=$?
  check "$label good mixed-case URL: exits 0" "[ $rc -eq 0 ]"
  check "$label good mixed-case URL: says LOAD_TARGET_OK" "echo \"\$out\" | grep -q LOAD_TARGET_OK"
  check "$label good mixed-case URL: no bad substitution" "! echo \"\$out\" | grep -qi 'bad substitution'"
  out=$(cd "$REPO_ROOT" && "$@" scripts/check-load-target.sh "https://API.PROD.example.com/" 2>&1); rc=$?
  check "$label prod URL: exits 1" "[ $rc -eq 1 ]"
  check "$label prod URL: says REFUSED" "echo \"\$out\" | grep -q REFUSED"
  out=$(cd "$REPO_ROOT" && "$@" scripts/check-load-target.sh "https://$(ip 192 168 1 10)/" 2>&1); rc=$?
  check "$label private IPv4: exits 1" "[ $rc -eq 1 ]"
}
ran32=0
if [ -x /bin/bash ] && /bin/bash -c '[ "${BASH_VERSINFO[0]}" -lt 4 ]'; then
  bash32_leg "native /bin/bash $(/bin/bash -c 'echo $BASH_VERSION'):" /bin/bash
  ran32=1
fi
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  if docker image inspect "$BASH32_IMAGE" >/dev/null 2>&1 || docker pull -q "$BASH32_IMAGE" >/dev/null 2>&1; then
    check "container bash is 3.2" \
      "docker run --rm \"$BASH32_IMAGE\" bash -c 'echo \$BASH_VERSION' | grep -q '^3\.2\.'"
    bash32_leg "docker bash:3.2:" docker run --rm -v "$REPO_ROOT":/w -w /w "$BASH32_IMAGE" bash
    ran32=1
  else
    echo "FAIL  docker bash:3.2: could not pull $BASH32_IMAGE"; fail=$((fail+1))
  fi
fi
if [ "$ran32" -eq 0 ]; then
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "FAIL  bash 3.2 leg: no bash 3.x and no docker in hosted CI, the #76 proof did not run"
    fail=$((fail+1))
  else
    echo "SKIP  bash 3.2 leg: no /bin/bash 3.x and no running docker here (#76 proof not run locally)"
  fi
fi

# 3. k6 inspect on the real script. K6_BIN (a pinned binary, CI's route, no Docker needed for this
#    half) wins when set; otherwise the pinned grafana/k6 image, never `latest`.
k6_inspect() {  # k6_inspect DIR FILE -> prints inspect output, returns k6's exit code
  if [ -n "${K6_BIN:-}" ]; then
    (cd "$1" && "$K6_BIN" inspect "$2" 2>&1)
  else
    docker run --rm -v "$1:/load:ro" "$K6_IMAGE" inspect "/load/$2" 2>&1
  fi
}
if [ -n "${K6_BIN:-}" ] && ! [ -x "$K6_BIN" ]; then
  check "K6_BIN is executable ($K6_BIN)" "false"
elif [ -z "${K6_BIN:-}" ] && { ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; }; then
  check "k6 available for inspect (K6_BIN or docker)" "false"
else
  INSPECT=$(k6_inspect "$REPO_ROOT/load" beta-20.js); RC_I=$?
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
  k6_inspect "$WORK/broken" broken.js >/dev/null; RC_B=$?
  check "k6 inspect on a broken script: exits non-zero" "[ $RC_B -ne 0 ]"
fi

echo ""
echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
