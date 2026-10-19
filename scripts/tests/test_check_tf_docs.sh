#!/usr/bin/env bash
# check-tf-docs.sh against fixture modules in a temp dir (never the live modules/): a fresh README passes;
# a stale one (the #11 AC), a missing README and missing or doubled markers each fail, naming the README;
# --fix makes a stale README pass again and leaves the hand-written prose alone. Needs terraform-docs.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
guard="$here/../check-tf-docs.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0

# new_module <dir>: one variable, one output, a README with prose and empty markers.
new_module() {
  mkdir -p "$1"
  cat >"$1/main.tf" <<'TF'
variable "name" {
  description = "Fixture name."
  type        = string
  default     = "fixture"
}

output "name" {
  description = "The fixture name."
  value       = var.name
}
TF
  printf '# fixture\n\nHand-written prose.\n\n<!-- BEGIN_TF_DOCS -->\n<!-- END_TF_DOCS -->\n' >"$1/README.md"
}

# run_case <name> <expect: pass|fail> <grep pattern the output must match, or -> [guard args...]
run_case() {
  local name=$1 expect=$2 pattern=$3
  shift 3
  local out rc
  out=$(bash "$guard" "$@" 2>&1)
  rc=$?
  if [ "$expect" = pass ]; then
    if [ $rc -ne 0 ]; then echo "FAIL $name: expected pass, got rc=$rc: $out"; failures=$((failures + 1)); return; fi
  else
    if [ $rc -eq 0 ]; then echo "FAIL $name: expected failure, guard passed: $out"; failures=$((failures + 1)); return; fi
    if ! printf '%s' "$out" | grep -qE "$pattern"; then echo "FAIL $name: failed but not for the right reason: $out"; failures=$((failures + 1)); return; fi
  fi
  echo "ok   $name"
}

# Fresh: generate, then check.
d="$tmp/fresh"; new_module "$d/m"
run_case fix-runs pass - --fix "$d"
run_case fresh pass - "$d"
grep -qxF 'Hand-written prose.' "$d/m/README.md" && echo "ok   fix-keeps-prose" || { echo "FAIL fix-keeps-prose"; failures=$((failures + 1)); }

# Stale (#11 AC): a variable added after the docs were generated.
d="$tmp/stale"; new_module "$d/m"; bash "$guard" --fix "$d" >/dev/null
printf '\nvariable "extra" {\n  description = "Added later."\n  type        = string\n}\n' >>"$d/m/main.tf"
run_case stale-new-variable fail 'stale/m/README.md: generated docs are stale' "$d"
bash "$guard" --fix "$d" >/dev/null
run_case stale-after-fix pass - "$d"

# Stale: the generated block edited by hand.
d="$tmp/handedit"; new_module "$d/m"; bash "$guard" --fix "$d" >/dev/null
sed 's/Fixture name\./Edited by hand./' "$d/m/README.md" >"$d/m/README.md.new" && mv "$d/m/README.md.new" "$d/m/README.md"
run_case stale-hand-edit fail 'handedit/m/README.md: generated docs are stale' "$d"

# No README.
d="$tmp/noreadme"; new_module "$d/m"; rm "$d/m/README.md"
run_case no-readme fail 'noreadme/m: no README.md' "$d"

# Markers missing, or doubled.
d="$tmp/nomarkers"; new_module "$d/m"; printf '# fixture\n' >"$d/m/README.md"
run_case no-markers fail 'nomarkers/m/README.md: needs exactly one' "$d"
d="$tmp/twomarkers"; new_module "$d/m"; printf '<!-- BEGIN_TF_DOCS -->\n<!-- END_TF_DOCS -->\n' >>"$d/m/README.md"
run_case doubled-markers fail 'twomarkers/m/README.md: needs exactly one' "$d"

# A dir with no module in it fails, so a moved modules/ can't silently skip the check.
mkdir -p "$tmp/empty"
run_case no-modules fail 'no module with \*.tf' "$tmp/empty"

if [ "$failures" -gt 0 ]; then
  echo "test_check_tf_docs: $failures failure(s)"
  exit 1
fi
echo "test_check_tf_docs: all passed"
