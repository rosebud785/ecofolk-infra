#!/usr/bin/env bash
# check-plan-tree.sh — ecofolk-infra#162 (Architect ruling c7084664707, option B; HCL-parse ruling c7086246324).
# Static refusals on a PR's tree BEFORE `terraform init` and before any credential exists: `terraform plan` executes
# PR-authored HCL, so a plan run that holds an identity is exposed to whatever that HCL can make Terraform run, fetch
# or write. This refuses a tree that could. A refused tree gets no PR-time plan; the apply's own plan is the first one.
#
# HOW: every .tf file and lockfile is PARSED by hcl2json (HashiCorp hcl/v2, the parser Terraform itself uses; pinned by
# sha256 in fetch-hcl2json.sh) and the rules (check-plan-tree.jq) are judged on the parse tree. A line scan cannot be
# right about HCL: Terraform accepts unquoted labels (`provider google {`) and a leading `/* … */` (ef-qa HOLD
# c7086176386). A file that does not PARSE is a refusal, never a pass.
#
# Refuses (each a named failure, `file: message`; the parse tree has no line numbers):
#   0. the TOP-LEVEL block kinds are an allowlist (Architect c7089836077): terraform, provider, variable, locals, output,
#      module, resource, data, moved, import, removed. `check` (a `data` block scoped in it is read at PLAN: ef-qa
#      c7089806892), `ephemeral`, `action`, `list` and any kind added later are refused by name. Resource and data blocks
#      are judged wherever they are nested as well (belt and braces behind this rule)
#   1. data "external" / data "http"  (a data source runs a program or a request at plan time)
#   2. a provider block for external / http / local / null, or for a provider not on the allowlist
#   3. (R6) resource and data TYPES are an ALLOWLIST: only google_* and archive_* (the prefixes of the allowlisted
#      providers). A denylist of provider names missed the BUILT-IN terraform_remote_state (a plan-time request to any
#      host, with plain-HCL config); terraform_data, random_*, external_*, http_*, local_* and null_* go the same way
#   3b. (R6 nit) an auto-loaded variable file in the planned root (terraform.tfvars, *.auto.tfvars, and their .json
#      forms), which would override the workflow's own TF_VAR_ values
#   4. any `provisioner` block
#   5. any module `source` that is not a local path (./ or ../) that resolves INSIDE the tree (so every module that
#      `init` loads has been read by these rules); any required_providers source outside the allowlist
#   6. any provider in a .terraform.lock.hcl outside the allowlist
#   7. any *.tf.json file (JSON HCL is not scanned, so not accepted)
#   8. any `output_path` that is not exactly "${path.root|module}/.terraform/tmp/<plain file name>" (R1): hashicorp/
#      archive's data source WRITES a zip at plan time, to wherever output_path says; pointed at a runner file-command
#      file it is code execution in a later step while the plan identity's credential file exists
#   9. the backend (R2): the planned root (environments/dev) must declare EXACTLY ONE `backend "gcs"` whose body is a
#      `prefix = "<literal>"` and nothing else, no `cloud` block, no other backend type anywhere, no backend in a module
#  10. a `*_custom_endpoint` attribute anywhere (a provider pointed at another host would send the access token there)
#  11. any symbolic link, and any committed `.terraform` directory (never scanned, yet `init` would read it)
#  12. (R5) a `provider "google"` / `"google-beta"` block takes an ATTRIBUTE ALLOWLIST: project, region, zone, alias and
#      default_labels (a map of plain values). Any other attribute or nested block is refused by name, so a credential,
#      a token, an impersonation, a universe change, a scope, a billing project, or anything a future provider version
#      adds is refused without anyone having to know its name
#  13. a .tf / lockfile that hcl2json cannot parse
# Fail closed: an unreadable tree, a missing hcl2json, an empty allowlist or an allowlist entry that is not
# `namespace/name` is an error.
#
# Usage: HCL2JSON=<path to the verified hcl2json> check-plan-tree.sh <tree-dir> <allowed-providers, comma-separated> [root]
# root = the planned root module, relative to the tree (default environments/dev).
# The allowlist is passed in by the caller and lives in infra-plan.yml ON MAIN, never in the PR's tree. This script, the
# jq rules and hcl2json are run from main's checkout against the PR's checkout.
# Exit: 0 clean; 1 a refusal (names each); 2 bad usage / unreadable tree / no hcl2json.
# Surface path (CODEOWNERS): weakening this needs ARCHITECT APPROVED.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dir="${1:-}"
allow_csv="${2:-}"
root="${3:-environments/dev}"
[ -n "$dir" ] && [ -d "$dir" ] || { echo "check-plan-tree: tree directory '$dir' not found" >&2; exit 2; }
[ -n "$allow_csv" ] || { echo "check-plan-tree: the provider allowlist is empty (fail closed)" >&2; exit 2; }
[[ "$root" =~ ^[A-Za-z0-9._/-]+$ ]] && [[ "$root" != *..* ]] || { echo "check-plan-tree: root '$root' is not a plain relative path" >&2; exit 2; }
[ -d "$dir/$root" ] || { echo "check-plan-tree: the planned root '$root' is not in the tree" >&2; exit 2; }
h2j="${HCL2JSON:-}"
[ -n "$h2j" ] && [ -x "$h2j" ] || { echo "check-plan-tree: HCL2JSON is not set to an executable (fetch-hcl2json.sh)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "check-plan-tree: jq is required" >&2; exit 2; }

# Portable to bash 3.2 (a Mac) as well as CI's bash 5: no associative arrays, no mapfile.
allow_json="["
first=1
IFS=',' read -r -a entries <<<"$allow_csv"
for e in "${entries[@]}"; do
  [[ "$e" =~ ^[a-z0-9-]+/[a-z0-9-]+$ ]] || { echo "check-plan-tree: allowlist entry '$e' is not namespace/name" >&2; exit 2; }
  [ "$first" = 1 ] || allow_json="$allow_json,"
  allow_json="$allow_json\"$e\""
  first=0
done
allow_json="$allow_json]"

tree_real="$(cd "$dir" && pwd -P)" || { echo "check-plan-tree: could not resolve $dir" >&2; exit 2; }

fail=0
report() { echo "$1: $2"; fail=1; }
# A message that quotes PR-controlled text: no backticks (the caller posts it in a fence), one line, cut.
clip() { printf '%s' "$1" | tr -d '`' | tr '\n\r' '  ' | cut -c1-"${2:-160}"; }

list_files() { # <find predicate…> -> NUL-separated paths; never under .git or .terraform
  find "$dir" \( -name .git -o -name .terraform \) -prune -o "$@" -print0
}
read_nul() { # fill the named array from NUL-separated stdin
  local name=$1 item
  eval "$name=()"
  while IFS= read -r -d '' item; do eval "$name+=(\"\$item\")"; done
}
find "$dir" -maxdepth 0 >/dev/null 2>&1 || { echo "check-plan-tree: could not list $dir" >&2; exit 2; }
read_nul tf_files < <(list_files -type f -name '*.tf')
read_nul json_files < <(list_files -type f -name '*.tf.json')
read_nul lock_files < <(list_files -type f -name '.terraform.lock.hcl')
read_nul link_files < <(list_files -type l)
# A committed .terraform directory (modules/, providers/) is read by `init` but never by these rules.
read_nul tfdirs < <(find "$dir" -name .git -prune -o -type d -name .terraform -print0)

# Variable files in the planned root are loaded AUTOMATICALLY and override the workflow's own TF_VAR_ values. They add no
# blocks, so this is not exploitable today; refusing them keeps the variable values the workflow's (Architect, R6 nit).
read_nul tfvars_files < <(find "$dir/$root" -maxdepth 1 -type f \( -name 'terraform.tfvars' -o -name 'terraform.tfvars.json' -o -name '*.auto.tfvars' -o -name '*.auto.tfvars.json' \) -print0)
for f in ${tfvars_files[@]+"${tfvars_files[@]}"}; do report "$f" "an auto-loaded variable file in the planned root is not accepted (the workflow's TF_VAR_ values are the only inputs)"; done

for f in ${json_files[@]+"${json_files[@]}"}; do report "$f" "*.tf.json is not accepted (JSON HCL is not scanned)"; done
for f in ${link_files[@]+"${link_files[@]}"}; do report "$f" "a symbolic link is not accepted"; done
for f in ${tfdirs[@]+"${tfdirs[@]}"}; do report "$f" "a committed .terraform directory is not accepted (init would read it, these rules would not)"; done

# kind_of <file>: where the file lives, for the backend rules.
kind_of() {
  local rel="${1#"$dir"/}"
  if [[ "$rel" == "$root"/* && "${rel#"$root"/}" != */* ]]; then echo root
  elif [[ "$rel" == modules/* ]]; then echo module
  elif [[ "$rel" == environments/*/* && "${rel#environments/*/}" != */* ]]; then echo env
  else echo other; fi
}

# parse <file> <mode> <kind>: hcl2json, then the jq rules; findings land in $findings. Non-zero if the file did not parse.
parse() {
  local f=$1 mode=$2 kind=$3 json rc
  # stderr is merged into the capture: on success hcl2json prints only JSON (anything else fails jq below, a refusal),
  # and on failure the text is the parse error.
  json="$("$h2j" "$f" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    report "$f" "does not parse as HCL, so it cannot be judged (a parse failure is a refusal): $(clip "$json" 140)"
    return 1
  fi
  if ! findings="$(printf '%s' "$json" | jq -r --arg mode "$mode" --arg kind "$kind" --argjson allow "$allow_json" -f "$here/check-plan-tree.jq" 2>&1)"; then
    report "$f" "could not be judged (the rules failed on its parse tree; a refusal): $(clip "$findings" 140)"
    return 1
  fi
  return 0
}

backends=0
for f in ${tf_files[@]+"${tf_files[@]}"}; do
  kind="$(kind_of "$f")"
  findings=""
  parse "$f" tf "$kind" || continue
  while IFS=$'\t' read -r tag rest; do
    case "$tag" in
      ERR) report "$f" "$rest" ;;
      BACKEND) backends=$((backends + 1)) ;;
      MODSRC)
        # A local module is only safe if it is INSIDE the tree: every module `init` loads must be one these rules read.
        target="$(cd "$(dirname "$f")" 2>/dev/null && cd "$rest" 2>/dev/null && pwd -P)"
        if [ -z "$target" ]; then
          report "$f" "module source \"$(clip "$rest" 80)\" is not a directory in the tree"
        elif [ "$target" != "$tree_real" ] && [[ "$target" != "$tree_real"/* ]]; then
          report "$f" "module source \"$(clip "$rest" 80)\" leaves the tree (its code would be planned but never read)"
        fi
        ;;
      "") ;;
      *) report "$f" "unexpected rule output: $(clip "$tag $rest" 80)" ;;
    esac
  done <<<"$findings"
done

for f in ${lock_files[@]+"${lock_files[@]}"}; do
  findings=""
  parse "$f" lock other || continue
  while IFS=$'\t' read -r tag rest; do
    case "$tag" in
      ERR) report "$f" "$rest" ;;
      "") ;;
      *) report "$f" "unexpected rule output: $(clip "$tag $rest" 80)" ;;
    esac
  done <<<"$findings"
done

# 9 (continued). The planned root declares exactly one gcs backend (its body was judged above).
[ "$backends" = 1 ] || report "$dir/$root" "the planned root must declare exactly one backend \"gcs\" (found $backends)"

if [ "$fail" -ne 0 ]; then
  echo "check-plan-tree: REFUSED. This tree gets no PR-time plan; the apply's own plan is the first one." >&2
  exit 1
fi
echo "check-plan-tree: ok (${#tf_files[@]} .tf file(s), ${#lock_files[@]} lockfile(s))"
