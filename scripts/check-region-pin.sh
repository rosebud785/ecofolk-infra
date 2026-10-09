#!/usr/bin/env bash
# check-region-pin.sh — CI guard for ef#391: fail the build if any GCP
# resource pins a region other than Montréal (northamerica-northeast1), or
# uses a "global" endpoint where a regional one is required (BUILD_PLAN.md
# §11.6: Vertex AI must use the Montréal regional endpoint, not global).
#
# WHY THIS EXISTS ALONGSIDE THE TERRAFORM VARIABLE VALIDATION
#   modules/project/variables.tf already refuses a WRONG
#   VALUE passed to its own `region` variable, via a `validation` block. That
#   catches a caller overriding the variable. It cannot catch a region string
#   hardcoded directly into some OTHER resource's arguments, bypassing that
#   variable entirely — e.g. `location = "us-central1"` typed straight into a
#   `google_sql_database_instance` block. This script is that second,
#   independent layer: it greps the actual committed config, not the
#   variable's own declared contract. Enforcement before any resource exists
#   is the only cheap time to do this — after something is provisioned, a
#   region violation costs a migration instead of a grep.
#
# THE #4547 LESSON THIS SCRIPT IS BUILT NOT TO REPEAT
#   Deployer's own regression guard on homeass#4547 matched its OWN SOURCE
#   FILE, because the file it scanned contained the very pattern it searched
#   for. This script only ever scans *.tf / *.tfvars files under the target
#   directory (default: the repo root) — never its own source, never a test
#   fixture directory. Proven, not assumed: see
#   scripts/tests/test_check_region_pin.sh, which points this script at
#   a throwaway fixture directory containing a DELIBERATE us-central1
#   violation and asserts the run actually goes red, then at a clean fixture
#   and asserts it goes green.
#
# USAGE
#   bash scripts/check-region-pin.sh [DIR]   # default DIR: the repo root
#
# EXIT: 0 = no disallowed region/endpoint token found in any *.tf/*.tfvars
#           file under DIR.
#       1 = at least one violation found. Prints file:line and the token.
#       2 = DIR does not exist, or the Terraform module's own declared
#           default/validation has drifted from this script's own
#           ALLOWED_REGION constant (checked below, not just asserted) —
#           refuses to report a verdict against a definition of "allowed"
#           it can no longer trust.

set -uo pipefail

# The ONE allowed region (ef#391, Andy's hydro-power constraint). Must match
# modules/project/variables.tf's own `region` default AND
# validation condition exactly — checked below, not just duplicated here on
# trust.
ALLOWED_REGION="northamerica-northeast1"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
DEFAULT_DIR="$REPO_ROOT"
TARGET_DIR="${1:-$DEFAULT_DIR}"
TF_VARS_FILE="$REPO_ROOT/modules/project/variables.tf"

RED=$'\033[31m'; GRN=$'\033[32m'; RST=$'\033[0m'
[ -t 1 ] || { RED=""; GRN=""; RST=""; }

[ -d "$TARGET_DIR" ] || { echo "${RED}GATE ERROR${RST}: no directory at $TARGET_DIR."; exit 2; }

# Self-consistency: this script's ALLOWED_REGION and the Terraform module's
# own default/validation must agree, or "allowed" means two different things
# in two places — exactly the drift ef#391 exists to prevent, pointed at
# itself. Only checked when scanning the real repo (a test fixture directory
# won't carry this file, and shouldn't need to).
if [ "$TARGET_DIR" = "$DEFAULT_DIR" ] && [ -f "$TF_VARS_FILE" ]; then
    tf_hits=$(grep -c "\"$ALLOWED_REGION\"" "$TF_VARS_FILE")
    if [ "$tf_hits" -lt 2 ]; then
        echo "${RED}GATE ERROR${RST}: $TF_VARS_FILE does not declare \"$ALLOWED_REGION\" as both its"
        echo "default and validation condition (found $tf_hits occurrence(s), expected >= 2)."
        echo "This script's ALLOWED_REGION and the Terraform module have drifted apart — fix one to"
        echo "match the other before trusting this guard's verdict."
        exit 2
    fi
fi

# GCP region-shaped token: <continent-ish>-<direction><digit>, e.g.
# us-central1, europe-west4, asia-southeast1, northamerica-northeast1. Also
# flags the bare word "global" (BUILD_PLAN.md §11.6: Vertex AI must use the
# regional endpoint, never global).
PATTERN='\b(us|europe|asia|australia|southamerica|northamerica|me|africa)-[a-z]+[0-9]\b|\bglobal\b'

violations=0
while IFS= read -r -d '' file; do
    while IFS=: read -r lineno match; do
        [ -n "$match" ] || continue
        [ "$match" = "$ALLOWED_REGION" ] && continue
        echo "${RED}FAIL${RST} $file:$lineno — disallowed region/endpoint token: $match"
        violations=$((violations + 1))
    done < <(grep -noE "$PATTERN" "$file")
done < <(find "$TARGET_DIR" -name .terraform -prune -o -type f \( -name '*.tf' -o -name '*.tfvars' \) -print0)

echo
if [ "$violations" -eq 0 ]; then
    echo "${GRN}REGION_PIN_OK${RST} — every region/endpoint token under $TARGET_DIR is $ALLOWED_REGION."
    exit 0
fi
echo "${RED}REGION_PIN_VIOLATION${RST} — $violations disallowed region/endpoint token(s) found."
echo "Andy's Quebec-hydro constraint is hard: everything must run in $ALLOWED_REGION. Fix the"
echo "file(s) above before this can pass."
exit 1
