#!/usr/bin/env bash
# test_policy_files.sh — proves policy-files.sh (ecofolk-infra#7, R1) scans the whole repo and goes red
# on JSON Terraform. Runs against THROWAWAY git repos, never the real tree.
#
# Usage: bash scripts/tests/test_policy_files.sh
# Exit: 0 if every case matches its expected outcome, 1 otherwise.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHK="$SCRIPT_DIR/../policy-files.sh"

pass=0; fail=0
check() {
  local name="$1" cond="$2"
  if eval "$cond"; then echo "PASS  $name"; pass=$((pass+1));
  else echo "FAIL  $name  (condition: $cond)"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkrepo() {
  git init -q "$1"
  git -C "$1" config user.email test@example.invalid
  git -C "$1" config user.name test
}

# 1. Files outside environments/ and modules/ MUST be listed: a local module under foo/ and the
#    top-level local-only/ that CODEOWNERS names.
R1="$WORK/wide"
mkrepo "$R1"
mkdir -p "$R1/environments/dev" "$R1/modules/net" "$R1/foo" "$R1/local-only" "$R1/environments/dev/.terraform/modules/x"
touch "$R1/main.tf" "$R1/environments/dev/main.tf" "$R1/modules/net/main.tf" "$R1/foo/main.tf" \
  "$R1/local-only/sa.tf" "$R1/environments/dev/notes.md" "$R1/untracked.tf" \
  "$R1/environments/dev/.terraform/modules/x/main.tf"
git -C "$R1" add main.tf environments/dev/main.tf environments/dev/notes.md modules/net/main.tf foo/main.tf local-only/sa.tf
OUT1=$(bash "$CHK" "$R1" 2>&1); RC1=$?
check "repo-wide: exits 0" "[ $RC1 -eq 0 ]"
check "repo-wide: lists foo/main.tf" "printf '%s\n' \"\$OUT1\" | grep -qx 'foo/main.tf'"
check "repo-wide: lists local-only/sa.tf" "printf '%s\n' \"\$OUT1\" | grep -qx 'local-only/sa.tf'"
check "repo-wide: lists root main.tf" "printf '%s\n' \"\$OUT1\" | grep -qx 'main.tf'"
check "repo-wide: lists environments/ and modules/" "[ \$(printf '%s\n' \"\$OUT1\" | grep -cE '^(environments/dev|modules/net)/main.tf\$') -eq 2 ]"
check "repo-wide: exactly the 5 tracked .tf files" "[ \$(printf '%s\n' \"\$OUT1\" | wc -l) -eq 5 ]"
check "repo-wide: skips untracked and .terraform/" "! printf '%s\n' \"\$OUT1\" | grep -qE 'untracked|\\.terraform/'"

# 2. A tracked *.tf.json MUST fail the job, naming the file.
R2="$WORK/json"
mkrepo "$R2"
mkdir -p "$R2/environments/dev"
touch "$R2/environments/dev/main.tf"
echo '{"resource": {"google_service_account_key": {"k": {}}}}' > "$R2/environments/dev/override.tf.json"
git -C "$R2" add environments/dev/main.tf environments/dev/override.tf.json
OUT2=$(bash "$CHK" "$R2" 2>&1); RC2=$?
check "tf.json: exits 1" "[ $RC2 -eq 1 ]"
check "tf.json: names the file" "printf '%s\n' \"\$OUT2\" | grep -q 'environments/dev/override.tf.json'"
check "tf.json: says why" "printf '%s\n' \"\$OUT2\" | grep -q \"JSON Terraform isn't policy-checked; write HCL\""

# 3. An untracked *.tf.json is not the repo's config and does not fail.
R3="$WORK/untracked-json"
mkrepo "$R3"
touch "$R3/main.tf" "$R3/scratch.tf.json"
git -C "$R3" add main.tf
bash "$CHK" "$R3" >/dev/null 2>&1; RC3=$?
check "untracked tf.json: exits 0" "[ $RC3 -eq 0 ]"

# 4. No tracked .tf at all is an error, not a silent pass.
R4="$WORK/empty"
mkrepo "$R4"
bash "$CHK" "$R4" >/dev/null 2>&1; RC4=$?
check "no .tf files: exits 1" "[ $RC4 -eq 1 ]"

echo "--- $pass passed, $fail failed"
[ "$fail" -eq 0 ]
