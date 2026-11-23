#!/usr/bin/env bash
# hcl2json-cached.sh — the test stand-in for hcl2json (ecofolk-infra#162, Architect permission ruling: hcl2json runs ONLY
# in CI). It answers `hcl2json <file>` for a file whose CONTENT has a committed answer in ./cache/<sha256>.json (rc 0)
# or ./cache/<sha256>.fail (rc 1, a parse failure). Locally that is all there is: the rules are judged on committed JSON.
#
# In CI the real, sha256-pinned binary is named by H2J_REAL; this script then runs IT (so a test run proves the rules on
# the real parse), and if H2J_RECORD names a directory it records each answer there, so verify-hcl-cache.sh can prove
# every committed cache entry is exactly what the real binary emits. A file with no committed answer, run locally, is
# rc 3 with a message that says so (never a silent pass): add it by running the tests in CI with H2J_RECORD set.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
f="${1:-}"
[ -f "$f" ] || { echo "hcl2json-cached: no such file: $f" >&2; exit 2; }
if command -v sha256sum >/dev/null 2>&1; then sum="$(sha256sum "$f" | cut -d' ' -f1)"; else sum="$(shasum -a 256 "$f" | cut -d' ' -f1)"; fi

if [ -n "${H2J_REAL:-}" ]; then
  out="$("$H2J_REAL" "$f" 2>&1)"; rc=$?
  if [ -n "${H2J_RECORD:-}" ]; then
    mkdir -p "$H2J_RECORD"
    if [ "$rc" = 0 ]; then printf '%s\n' "$out" | jq -cS . >"$H2J_RECORD/$sum.json"; else echo "parse error" >"$H2J_RECORD/$sum.fail"; fi
  fi
  printf '%s\n' "$out"
  exit "$rc"
fi

if [ -f "$here/cache/$sum.json" ]; then cat "$here/cache/$sum.json"; exit 0; fi
if [ -f "$here/cache/$sum.fail" ]; then echo "Failed to convert file: parse config: (recorded parse failure)"; exit 1; fi
echo "hcl2json-cached: no committed hcl2json output for the content of $(basename "$f") (sha256 $sum); record it by running the tests in CI with H2J_RECORD set" >&2
exit 3
