#!/usr/bin/env bash
# test_check_region_pin.sh — proves check-region-pin.sh (ef#391) can actually
# fail, not just that it passes on config that was never going to trip it.
#
# Deployer's own regression guard on homeass#4547 matched its OWN SOURCE
# FILE, because the file it scanned contained the pattern it searched for —
# a guard that can only ever go green was never really tested. This suite
# points check-region-pin.sh at a THROWAWAY fixture directory (never its own
# source, never the real repo tree), with a deliberate us-central1
# violation, and asserts the run goes red. Only then does it check the clean
# case.
#
# Usage: bash scripts/tests/test_check_region_pin.sh
# Exit: 0 if every case matches its expected outcome, 1 otherwise.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHK="$SCRIPT_DIR/../check-region-pin.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# bash 3.2 image for the #76 leg, pinned by digest (bash:3.2).
BASH32_IMAGE="bash@sha256:0fd7cb8499c63a3c9345e7088a9cd83bb69f6e895e83833859aff838a0312091"

pass=0; fail=0
check() {
  local name="$1" cond="$2"
  if eval "$cond"; then echo "PASS  $name"; pass=$((pass+1));
  else echo "FAIL  $name  (condition: $cond)"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
FIX32=""
trap 'rm -rf "$WORK" ${FIX32:+"$FIX32"}' EXIT

# 1. A deliberate us-central1 violation MUST fail the build — the actual
#    proof this guard can go red, not an assumption.
VIOLATION="$WORK/violation"
mkdir -p "$VIOLATION"
cat > "$VIOLATION/main.tf" <<'EOF'
resource "google_sql_database_instance" "main" {
  region = "us-central1"
}
EOF
OUT1=$(bash "$CHK" "$VIOLATION" 2>&1); RC1=$?
check "us-central1 fixture: exits 1" "[ $RC1 -eq 1 ]"
check "us-central1 fixture: names the file and token" "echo \"\$OUT1\" | grep -q 'main.tf.*us-central1'"
check "us-central1 fixture: reports REGION_PIN_VIOLATION" "echo \"\$OUT1\" | grep -q REGION_PIN_VIOLATION"

# 2. A deliberate "global" violation (BUILD_PLAN.md §11.6: Vertex AI must be
#    regional) must also fail.
GLOBAL_VIOLATION="$WORK/global-violation"
mkdir -p "$GLOBAL_VIOLATION"
cat > "$GLOBAL_VIOLATION/main.tf" <<'EOF'
resource "google_vertex_ai_endpoint" "main" {
  location = "global"
}
EOF
OUT2=$(bash "$CHK" "$GLOBAL_VIOLATION" 2>&1); RC2=$?
check "global fixture: exits 1" "[ $RC2 -eq 1 ]"
check "global fixture: names the token" "echo \"\$OUT2\" | grep -q 'global'"

# 3. A clean fixture, using ONLY the allowed region, must pass.
CLEAN="$WORK/clean"
mkdir -p "$CLEAN"
cat > "$CLEAN/main.tf" <<'EOF'
resource "google_sql_database_instance" "main" {
  region = "northamerica-northeast1"
}
EOF
OUT3=$(bash "$CHK" "$CLEAN" 2>&1); RC3=$?
check "clean fixture: exits 0" "[ $RC3 -eq 0 ]"
check "clean fixture: reports REGION_PIN_OK" "echo \"\$OUT3\" | grep -q REGION_PIN_OK"

# 4. A directory with no .tf/.tfvars files at all is vacuously clean, not an
#    error — an empty scaffold must not read as a failure.
EMPTY="$WORK/empty"
mkdir -p "$EMPTY"
OUT4=$(bash "$CHK" "$EMPTY" 2>&1); RC4=$?
check "empty dir: exits 0" "[ $RC4 -eq 0 ]"

# 5. A missing directory refuses to report a verdict, rather than silently
#    treating "nothing found" the same as "nothing scanned".
OUT5=$(bash "$CHK" "$WORK/does-not-exist" 2>&1); RC5=$?
check "missing dir: exits 2" "[ $RC5 -eq 2 ]"
check "missing dir: names the reason" "echo \"\$OUT5\" | grep -qi 'GATE ERROR'"

# 6. THE #4547 CHECK ITSELF: run against this script's own real target
#    (the repo root, no override) and confirm it does NOT match its own
#    source or this test's own fixtures above — only *.tf/*.tfvars under
#    the repo are ever in scope. If this fails, the guard has started
#    scanning something it shouldn't.
OUT6=$(bash "$CHK" 2>&1); RC6=$?
check "real repo tree: exits 0 (skeleton is clean)" "[ $RC6 -eq 0 ]"
check "real repo tree: never mentions this script's own path" \
  "! echo \"\$OUT6\" | grep -q 'check-region-pin.sh'"

# 7. Self-consistency: the Terraform module's default/validation must still
#    agree with this script's own ALLOWED_REGION. Prove the check actually
#    fires by pointing it at a variables.tf that has drifted.
DRIFT="$WORK/drift"
mkdir -p "$DRIFT/modules/project"
mkdir -p "$DRIFT/scripts"
cat > "$DRIFT/modules/project/variables.tf" <<'EOF'
variable "region" {
  default = "us-east1"
}
EOF
cp "$CHK" "$DRIFT/scripts/check-region-pin.sh"
OUT7=$(cd "$DRIFT" && bash scripts/check-region-pin.sh 2>&1); RC7=$?
check "drifted Terraform default: exits 2" "[ $RC7 -eq 2 ]"
check "drifted Terraform default: names the drift" "echo \"\$OUT7\" | grep -qi 'drifted apart'"

# 8. Case-insensitive matching (#26). GCS reports a bucket's `location` in
#    upper case, so the pattern must see region tokens in any case. Before
#    #26 an upper-case US-CENTRAL1 slipped through: the known-wrong case.
UPPER_VIOLATION="$WORK/upper-violation"
mkdir -p "$UPPER_VIOLATION"
cat > "$UPPER_VIOLATION/main.tf" <<'EOF'
resource "google_storage_bucket" "media" {
  location = "US-CENTRAL1"
}
EOF
OUT8=$(bash "$CHK" "$UPPER_VIOLATION" 2>&1); RC8=$?
check "upper-case US-CENTRAL1 fixture: exits 1" "[ $RC8 -eq 1 ]"
check "upper-case US-CENTRAL1 fixture: names the token as written" "echo \"\$OUT8\" | grep -q 'main.tf.*US-CENTRAL1'"

# 9. Mixed case and an upper-case GLOBAL are caught the same way.
MIXED_VIOLATION="$WORK/mixed-violation"
mkdir -p "$MIXED_VIOLATION"
cat > "$MIXED_VIOLATION/main.tf" <<'EOF'
resource "google_storage_bucket" "media" {
  location = "Europe-West4"
}
resource "google_vertex_ai_endpoint" "main" {
  location = "GLOBAL"
}
EOF
OUT9=$(bash "$CHK" "$MIXED_VIOLATION" 2>&1); RC9=$?
check "mixed-case fixture: exits 1" "[ $RC9 -eq 1 ]"
check "mixed-case fixture: names Europe-West4" "echo \"\$OUT9\" | grep -q 'Europe-West4'"
check "mixed-case fixture: names GLOBAL" "echo \"\$OUT9\" | grep -q 'GLOBAL'"
check "mixed-case fixture: counts both tokens" "echo \"\$OUT9\" | grep -q '2 disallowed'"

# 10. The allowed region in upper case (the form GCS reports for a bucket
#     `location`) is the allowed region, matched like lower case: it passes.
UPPER_CLEAN="$WORK/upper-clean"
mkdir -p "$UPPER_CLEAN"
cat > "$UPPER_CLEAN/main.tf" <<'EOF'
resource "google_storage_bucket" "media" {
  location = "NORTHAMERICA-NORTHEAST1"
}
EOF
OUT10=$(bash "$CHK" "$UPPER_CLEAN" 2>&1); RC10=$?
check "upper-case NORTHAMERICA-NORTHEAST1 fixture: exits 0" "[ $RC10 -eq 0 ]"
check "upper-case NORTHAMERICA-NORTHEAST1 fixture: reports REGION_PIN_OK" "echo \"\$OUT10\" | grep -q REGION_PIN_OK"

# 11. Fail closed (#76): if a tool the scan depends on breaks, the verdict is
#     a GATE ERROR (exit 2), never REGION_PIN_OK. Shims on PATH stand in for
#     a broken grep and a broken lower-casing `tr`.
SHIM_GREP="$WORK/shim-grep"; SHIM_TR="$WORK/shim-tr"
mkdir -p "$SHIM_GREP" "$SHIM_TR"
printf '#!/bin/sh\necho "grep: simulated read error" >&2\nexit 2\n' > "$SHIM_GREP/grep"
REAL_TR="$(command -v tr)"
cat > "$SHIM_TR/tr" <<EOF
#!/bin/sh
[ "\$1" = '[:upper:]' ] && { echo "tr: simulated failure" >&2; exit 1; }
exec "$REAL_TR" "\$@"
EOF
chmod +x "$SHIM_GREP/grep" "$SHIM_TR/tr"
OUT11=$(PATH="$SHIM_GREP:$PATH" bash "$CHK" "$VIOLATION" 2>&1); RC11=$?
check "broken grep: exits 2, not 0" "[ $RC11 -eq 2 ]"
check "broken grep: names the reason" "echo \"\$OUT11\" | grep -q 'GATE ERROR.*grep failed'"
OUT12=$(PATH="$SHIM_TR:$PATH" bash "$CHK" "$CLEAN" 2>&1); RC12=$?
check "broken lower-casing: exits 2, not 0" "[ $RC12 -eq 2 ]"
check "broken lower-casing: never reports REGION_PIN_OK" "! echo \"\$OUT12\" | grep -q REGION_PIN_OK"

# 12. bash 3.2 (#76): macOS /bin/bash is 3.2, where the old `${var,,}` was a
#     "bad substitution" that aborted the scan and then reported
#     REGION_PIN_OK (exit 0) on a us-central1 fixture. Re-run the known-wrong
#     and known-right fixtures under a real bash 3.2: natively when /bin/bash
#     is 3.x (a Mac), and in the bash:3.2 container when docker is up, using
#     the exact form `docker run --rm -v "$PWD":/w -w /w <bash:3.2> bash
#     scripts/check-region-pin.sh <fixture>`. The fixtures live in a
#     throwaway, git-ignored dir under the repo so that /w mount can see them,
#     and are removed on exit before anything else scans the tree. In hosted
#     CI (GITHUB_ACTIONS=true) the container leg is required, not skipped.
FIX32="$(mktemp -d "$REPO_ROOT/.region-pin-fixtures.XXXXXX")"
FIX32_REL="${FIX32#"$REPO_ROOT"/}"
mkdir -p "$FIX32/violation" "$FIX32/upper-violation" "$FIX32/clean" "$FIX32/upper-clean"
printf 'resource "google_sql_database_instance" "main" {\n  region = "us-central1"\n}\n' > "$FIX32/violation/main.tf"
printf 'resource "google_storage_bucket" "media" {\n  location = "US-CENTRAL1"\n}\n' > "$FIX32/upper-violation/main.tf"
printf 'resource "google_sql_database_instance" "main" {\n  region = "northamerica-northeast1"\n}\n' > "$FIX32/clean/main.tf"
printf 'resource "google_storage_bucket" "media" {\n  location = "NORTHAMERICA-NORTHEAST1"\n}\n' > "$FIX32/upper-clean/main.tf"

# bash32_leg LABEL CMD...  — CMD is run from the repo root with the fixture
# path (relative to the repo root) appended.
bash32_leg() {
  local label="$1"; shift
  local rc out
  for case in violation:1 upper-violation:1 clean:0 upper-clean:0; do
    out=$(cd "$REPO_ROOT" && "$@" scripts/check-region-pin.sh "$FIX32_REL/${case%%:*}" 2>&1); rc=$?
    check "$label ${case%%:*} fixture: exits ${case##*:}" "[ $rc -eq ${case##*:} ]"
    check "$label ${case%%:*} fixture: no bad substitution" "! echo \"\$out\" | grep -qi 'bad substitution'"
  done
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
rm -rf "$FIX32"; FIX32=""
if [ "$ran32" -eq 0 ]; then
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "FAIL  bash 3.2 leg: no bash 3.x and no docker in hosted CI — the #76 proof did not run"
    fail=$((fail+1))
  else
    echo "SKIP  bash 3.2 leg: no /bin/bash 3.x and no running docker here (#76 proof not run locally)"
  fi
fi

echo ""
echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
