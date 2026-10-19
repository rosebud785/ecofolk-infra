#!/usr/bin/env bash
# check-tf-docs.sh — ecofolk-infra#11: every module's README.md carries terraform-docs output that matches
# its *.tf. Fails, naming the module, if a modules/<name>/ with *.tf:
#   1. has no README.md;
#   2. has a README.md without exactly one `<!-- BEGIN_TF_DOCS -->` and one `<!-- END_TF_DOCS -->` line;
#   3. has a generated block that differs from what terraform-docs produces now (drift).
# Config: .terraform-docs.yml at the repo root. Prose outside the markers is hand-written and never checked.
# Usage: check-tf-docs.sh [--fix] [modules-dir]   (default modules; --fix regenerates the blocks in place)
set -euo pipefail

fix=0
if [ "${1:-}" = "--fix" ]; then fix=1; shift; fi
dir="${1:-modules}"
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
config="${TF_DOCS_CONFIG:-$root/.terraform-docs.yml}"

if ! command -v terraform-docs >/dev/null 2>&1; then
  echo "check-tf-docs: terraform-docs is required (README: Running the checks locally)" >&2
  exit 2
fi

fail=0
n=0
shopt -s nullglob
for m in "$dir"/*/; do
  m="${m%/}"
  tfs=("$m"/*.tf)
  [ ${#tfs[@]} -gt 0 ] || continue
  n=$((n + 1))
  readme="$m/README.md"
  if [ ! -f "$readme" ]; then
    echo "$m: no README.md (add one with the BEGIN_TF_DOCS/END_TF_DOCS markers, then run --fix)"
    fail=1
    continue
  fi
  b=$(grep -cxF '<!-- BEGIN_TF_DOCS -->' "$readme" || true)
  e=$(grep -cxF '<!-- END_TF_DOCS -->' "$readme" || true)
  if [ "$b" != 1 ] || [ "$e" != 1 ]; then
    echo "$readme: needs exactly one <!-- BEGIN_TF_DOCS --> and one <!-- END_TF_DOCS --> line (found $b and $e)"
    fail=1
    continue
  fi
  if [ "$fix" = 1 ]; then
    terraform-docs --config "$config" "$m" >/dev/null
  elif ! terraform-docs --config "$config" --output-check "$m" >/dev/null 2>&1; then
    echo "$readme: generated docs are stale; run: bash scripts/check-tf-docs.sh --fix"
    fail=1
  fi
done

if [ "$n" -eq 0 ]; then
  echo "check-tf-docs: no module with *.tf under $dir" >&2
  exit 1
fi
if [ "$fail" = 1 ]; then
  echo "check-tf-docs: FAILED" >&2
  exit 1
fi
if [ "$fix" = 1 ]; then echo "check-tf-docs: regenerated $n module(s)"; else echo "check-tf-docs: ok ($n module(s))"; fi
