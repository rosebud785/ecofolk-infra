#!/usr/bin/env bash
# verify-hcl-cache.sh — CI only (ecofolk-infra#162). Proves the committed answers in ./cache are EXACTLY what the pinned
# hcl2json emits. Usage: verify-hcl-cache.sh <record-dir> (the directory the tests wrote with H2J_RECORD set, by the
# real binary). Fails on: a recorded answer with no committed one (an uncached fixture), or one that differs; and on a
# committed .json that no fixture used any more (stale; it would mislead a local run).
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
rec="${1:-}"
[ -d "$rec" ] || { echo "verify-hcl-cache: record dir '$rec' not found" >&2; exit 2; }
fail=0
n=0
for r in "$rec"/*.json "$rec"/*.fail; do
  [ -e "$r" ] || continue
  n=$((n + 1))
  b="$(basename "$r")"
  if [ ! -f "$here/cache/$b" ]; then echo "UNCACHED: $b (a fixture's content has no committed answer; commit the recorded one)"; fail=1; continue; fi
  case "$b" in
    *.json) [ "$(jq -cS . "$r")" = "$(jq -cS . "$here/cache/$b")" ] || { echo "DIFFERS: $b (the committed answer is not what the pinned hcl2json emits)"; fail=1; } ;;
    *.fail) : ;;
  esac
done
for c in "$here"/cache/*.json "$here"/cache/*.fail; do
  [ -e "$c" ] || continue
  b="$(basename "$c")"
  [ -f "$rec/$b" ] || { echo "STALE: $b (committed, but no fixture produced it)"; fail=1; }
done
[ "$n" -gt 0 ] || { echo "verify-hcl-cache: nothing was recorded (did the tests run with H2J_REAL and H2J_RECORD?)"; exit 1; }
[ "$fail" = 0 ] && echo "verify-hcl-cache: ok ($n recorded answers match the committed cache)"
exit "$fail"
