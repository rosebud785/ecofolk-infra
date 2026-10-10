#!/usr/bin/env bash
# test_secret_scan.sh — proves .gitleaks.toml (#33) can actually fail, one planted fake at a time,
# and passes on a clean file. Same idea as test_check_region_pin.sh: a guard that can only ever go
# green was never tested.
#
# Fixtures are written into a mktemp -d at run time, NEVER into the repo: a committed fixture would
# trip the real full-history scan. For the same reason this file never holds a fake as a literal;
# each one is assembled from pieces, so the source itself does not match any rule.
#
# Usage: bash scripts/tests/test_secret_scan.sh   (needs `gitleaks` on PATH, or GITLEAKS=/path)
# Exit: 0 if every case matches its expected outcome, 1 otherwise.
# Surface path (CODEOWNERS): weakening this needs ARCHITECT APPROVED.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../../.gitleaks.toml"
GITLEAKS="${GITLEAKS:-gitleaks}"

if ! command -v "$GITLEAKS" >/dev/null 2>&1; then
  echo "FAIL  gitleaks not found (set GITLEAKS or put it on PATH)"
  exit 1
fi

pass=0; fail=0
check() {
  local name="$1" cond="$2"
  if eval "$cond"; then echo "PASS  $name"; pass=$((pass+1));
  else echo "FAIL  $name  (condition: $cond)"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# scan <file> -> gitleaks exit code (0 clean, 1 leak, anything else is an error)
scan() {
  "$GITLEAKS" dir --config "$CONFIG" --redact --exit-code 1 --no-banner --log-level error "$1" >/dev/null 2>&1
  echo $?
}

rand() { LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1"; }

# Each fake gets its own directory, so a pass/fail is about that one plant only.
plant() {
  local name="$1" content="$2"
  mkdir -p "$WORK/$name"
  printf '%s\n' "$content" > "$WORK/$name/main.tf"
  echo "$WORK/$name/main.tf"
}

dot="."
f=$(plant rfc1918 "host_ip = \"192${dot}168${dot}$((RANDOM % 250 + 1))${dot}$((RANDOM % 250 + 1))\"")
check "RFC1918 IPv4 fixture: gitleaks fails" "[ $(scan "$f") -eq 1 ]"

f=$(plant lan-host "endpoint = \"nas-$(rand 4 | tr 'A-Z' 'a-z')${dot}home${dot}arpa\"")
check ".home.arpa host fixture: gitleaks fails" "[ $(scan "$f") -eq 1 ]"

at="@"
f=$(plant email "owner = \"jane${dot}doe${at}mailbox-example${dot}net\"")
check "personal email fixture: gitleaks fails" "[ $(scan "$f") -eq 1 ]"

dashes="-----"
f=$(plant pem "$(printf '%sBEGIN RSA %s%s\n%s\n%sEND RSA %s%s' \
  "$dashes" "PRIVATE KEY" "$dashes" "$(rand 64)" "$dashes" "PRIVATE KEY" "$dashes")")
check "PEM private-key fixture: gitleaks fails" "[ $(scan "$f") -eq 1 ]"

f=$(plant password "password = \"$(rand 24)\"")
check "password = \"<random>\" fixture: gitleaks fails" "[ $(scan "$f") -eq 1 ]"

# Clean: ordinary Terraform, an allowlisted GitHub noreply address, and an interpolated SA address.
f=$(plant clean "$(cat <<TF
resource "google_compute_network" "vpc" {
  name    = "ecofolk-vpc"
  project = var.project_id
}

locals {
  bot     = "ecofolk-bot${at}users${dot}noreply${dot}github${dot}com"
  run_sa  = "\${var.name}${at}\${var.project_id}${dot}iam${dot}gserviceaccount${dot}com"
  region  = "northamerica-northeast1"
}
TF
)")
check "clean fixture: gitleaks passes" "[ $(scan "$f") -eq 0 ]"

echo "---"
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
