#!/usr/bin/env bash
# plan-summary.sh — ecofolk-infra#162 (Architect ruling c7084664707, option B). Turns `terraform show -json <plan>`
# into (a) a NAMES-ONLY PR comment and (b) a normalized hash, so the plan a reviewer read can be compared with the
# plan the apply computes. The repo is public, so a comment carries NO values, sensitive or not: for each changed
# resource, its address, its actions and the NAMES of the attributes that change. Never a before/after value.
#
#   plan-summary.sh hash    <plan.json>              sha256 of the sorted `address|actions|attribute-names` lines (hex)
#   plan-summary.sh record  <plan.json> <head-sha>   the machine line: `plan-record: <head-sha> <hash>`
#   plan-summary.sh comment <plan.json> <head-sha>   the markdown comment body (ends with the record line)
#
# The hash covers exactly what the comment shows: resource addresses, their actions and the NAMES of the attributes
# that change (no-op and read-only entries excluded). So an apply that updates the same resource with different
# attributes than the reviewer saw does not match. It does not cover attribute values, which the comment never shows.
# Run from MAIN's checkout against the PR's plan: the PR's own scripts are never executed.
# Exit: 0 ok; 2 bad usage or an unreadable/odd plan (never an empty "no changes" from a plan that did not parse).
# Surface path (CODEOWNERS): weakening this needs ARCHITECT APPROVED.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mode="${1:-}"; plan="${2:-}"; head="${3:-}"
command -v jq >/dev/null 2>&1 || { echo "plan-summary: jq is required" >&2; exit 2; }
[ -r "$plan" ] || { echo "plan-summary: plan json '$plan' not readable" >&2; exit 2; }
# A plan that does not parse, or has no resource_changes array, is an error: absent != empty.
jq -e '(.resource_changes | type) == "array"' "$plan" >/dev/null 2>&1 \
  || { echo "plan-summary: $plan has no resource_changes array (not a terraform show -json plan)" >&2; exit 2; }

# Pure no-op and read-only data reads are not changes. One `address|actions|changed attribute names` line per change,
# byte-sorted. The names are the same ones the comment shows (plan-names.jq), in full, never a value.
lines() {
  jq -r -L "$here" 'include "plan-names"; changed | .[] | hash_line' "$plan" | LC_ALL=C sort
}
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
hash() { lines | sha256; }

case "$mode" in
  hash) hash ;;
  record | comment)
    [[ "$head" =~ ^[0-9a-f]{40}$ ]] || { echo "plan-summary: head sha must be 40 lowercase hex" >&2; exit 2; }
    rec="plan-record: $head $(hash)"
    if [ "$mode" = record ]; then echo "$rec"; exit 0; fi
    jq -r -L "$here" --arg head "$head" --arg rec "$rec" -f "$here/plan-summary.jq" "$plan"
    ;;
  *) echo "usage: plan-summary.sh hash|record|comment <plan.json> [head-sha]" >&2; exit 2 ;;
esac
