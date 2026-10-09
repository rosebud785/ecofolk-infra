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

pass=0; fail=0
check() {
  local name="$1" cond="$2"
  if eval "$cond"; then echo "PASS  $name"; pass=$((pass+1));
  else echo "FAIL  $name  (condition: $cond)"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

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

echo ""
echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
