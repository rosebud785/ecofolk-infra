#!/usr/bin/env bash
# check-plan-tree.sh — ecofolk-infra#162 (Architect ruling c7084664707, option B). Static refusals on a PR's tree
# BEFORE `terraform init` and before any credential exists: `terraform plan` executes PR-authored HCL, so a plan run
# that holds an identity is exposed to whatever the PR's HCL can make Terraform run. This refuses a tree that could
# run code at plan time. A refused tree gets no PR-time plan; the apply's own plan is the first one, as before.
#
# Refuses (each a named failure, file:line):
#   1. data "external" / data "http"  (a data source runs a program or a request at plan time)
#   2. provider "external" / "http" / "local" / "null"
#   3. a resource or data block of a type from those providers (external_*, http_*, local_*, null_*): the provider
#      loads without a provider block, so rule 2 alone would miss it
#   4. any `provisioner` block
#   5. any module or provider `source` that is not a local path (./ or ../) or an allowlisted provider
#   6. any provider in a .terraform.lock.hcl outside the allowlist
#   7. any *.tf.json file (JSON HCL: not scanned, so not accepted)
# Fail closed: an unreadable tree, an empty allowlist or an allowlist entry that is not `namespace/name` is an error.
#
# Usage: check-plan-tree.sh <tree-dir> <allowed-providers, comma-separated, e.g. hashicorp/google,hashicorp/google-beta>
# The allowlist is passed in by the caller and lives in infra-plan.yml ON MAIN, never in the PR's tree. This script is
# run from main's checkout against the PR's checkout.
# Exit: 0 clean; 1 a refusal (names each); 2 bad usage / unreadable tree.
# Surface path (CODEOWNERS): weakening this needs ARCHITECT APPROVED.
set -uo pipefail

dir="${1:-}"
allow_csv="${2:-}"
[ -n "$dir" ] && [ -d "$dir" ] || { echo "check-plan-tree: tree directory '$dir' not found" >&2; exit 2; }
[ -n "$allow_csv" ] || { echo "check-plan-tree: the provider allowlist is empty (fail closed)" >&2; exit 2; }

# Portable to bash 3.2 (a Mac) as well as CI's bash 5: no associative arrays, no mapfile.
allowed=","
IFS=',' read -r -a entries <<<"$allow_csv"
for e in "${entries[@]}"; do
  [[ "$e" =~ ^[a-z0-9-]+/[a-z0-9-]+$ ]] || { echo "check-plan-tree: allowlist entry '$e' is not namespace/name" >&2; exit 2; }
  allowed="$allowed$e,"
done

fail=0
report() { echo "$1:$2: $3"; fail=1; }

# Every .tf file (and lockfile) in the tree, never under .git or .terraform. NUL-separated so a name with a space is
# one path. A find error is an error, not "nothing found".
list_files() { # <name pattern> -> NUL-separated paths on stdout; a find error is an error
  find "$dir" \( -name .git -o -name .terraform \) -prune -o -type f -name "$1" -print0
}
# Fill the named array from NUL-separated stdin.
read_nul() {
  local name=$1 item
  eval "$name=()"
  while IFS= read -r -d '' item; do eval "$name+=(\"\$item\")"; done
}
find "$dir" -maxdepth 0 >/dev/null 2>&1 || { echo "check-plan-tree: could not list $dir" >&2; exit 2; }
read_nul tf_files < <(list_files '*.tf')
read_nul json_files < <(list_files '*.tf.json')
read_nul lock_files < <(list_files '.terraform.lock.hcl')

for f in ${json_files[@]+"${json_files[@]}"}; do report "$f" 1 "*.tf.json is not accepted (JSON HCL is not scanned)"; done

# Provider source -> allowed? Accepts `ns/name` and `registry.terraform.io/ns/name`; anything else is not a provider.
provider_ok() {
  local s=${1#registry.terraform.io/}
  [[ "$s" =~ ^[a-z0-9-]+/[a-z0-9-]+$ ]] && [[ "$allowed" == *",$s,"* ]]
}

for f in "${tf_files[@]}"; do
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    # A whole-line comment is not code. (A block comment or an inline one is not stripped: that can only add refusals.)
    case "$line" in
      [[:space:]]'#'* | '#'* | [[:space:]]'//'* | '//'*) continue ;;
    esac
    [[ "$line" =~ ^[[:space:]]*(#|//) ]] && continue

    if [[ "$line" =~ ^[[:space:]]*data[[:space:]]+\"(external|http)\" ]]; then
      report "$f" "$n" "data \"${BASH_REMATCH[1]}\" runs code or a request at plan time"
    fi
    if [[ "$line" =~ ^[[:space:]]*provider[[:space:]]+\"(external|http|local|null)\" ]]; then
      report "$f" "$n" "provider \"${BASH_REMATCH[1]}\" is not accepted in a PR-time plan"
    fi
    if [[ "$line" =~ ^[[:space:]]*(resource|data)[[:space:]]+\"(external|http|local|null)(_[a-z0-9_]*)?\" ]]; then
      report "$f" "$n" "${BASH_REMATCH[1]} \"${BASH_REMATCH[2]}${BASH_REMATCH[3]}\" belongs to a provider that is not accepted in a PR-time plan"
    fi
    if [[ "$line" =~ ^[[:space:]]*provisioner[[:space:]]+\" ]]; then
      report "$f" "$n" "provisioner blocks are not accepted in a PR-time plan"
    fi
    if [[ "$line" =~ ^[[:space:]]*source[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
      src="${BASH_REMATCH[1]}"
      case "$src" in
        ./* | ../*) ;; # a local module
        *)
          provider_ok "$src" || report "$f" "$n" "source \"$src\" is neither a local path nor an allowlisted provider"
          ;;
      esac
    fi
    # A non-literal `source = expr` is ignored on purpose: a module or provider source must be a string literal
    # (Terraform refuses anything else at init), so it can only be a plain attribute such as a bucket object's source.
    # Any string-literal source anywhere is checked above, so a local-looking attribute path is the only false positive.
  done <"$f"
done

for f in "${lock_files[@]}"; do
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if [[ "$line" =~ ^provider[[:space:]]+\"([^\"]+)\" ]]; then
      p="${BASH_REMATCH[1]}" # copied first: provider_ok runs its own regex and would clobber BASH_REMATCH
      provider_ok "$p" || report "$f" "$n" "lockfile provider \"$p\" is not in the allowlist"
    fi
  done <"$f"
done

if [ "$fail" -ne 0 ]; then
  echo "check-plan-tree: REFUSED. This tree gets no PR-time plan; the apply's own plan is the first one." >&2
  exit 1
fi
echo "check-plan-tree: ok (${#tf_files[@]} .tf file(s), ${#lock_files[@]} lockfile(s))"
