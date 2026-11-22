#!/usr/bin/env bash
# Known-wrong fixture per refusal rule of check-plan-tree.sh (each must be refused, for the right reason), clean
# fixtures (must pass), and the live repo tree (must pass: it is what a docs-only PR looks like). Fixtures live in a
# temp dir. Positive control: the clean fixture shares every file with the bad ones except the one line under test.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
guard="$here/../check-plan-tree.sh"
repo="$here/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
ALLOW=hashicorp/google,hashicorp/google-beta,hashicorp/archive

LOCK_OK='provider "registry.terraform.io/hashicorp/google" {
  version = "5.1.0"
}
'
VERSIONS_OK='terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  backend "gcs" {
    prefix = "dev"
  }
}
'

# run_case <name> <expected rc> <pattern the output must match> <allowlist>   (main.tf body on stdin)
# Optional env: LOCK (lockfile body), EXTRA_FILE / EXTRA_BODY (a second file).
run_case() {
  local name=$1 want=$2 pattern=$3 allow=${4:-$ALLOW} d="$tmp/$1" out rc
  mkdir -p "$d/environments/dev" "$d/modules/m"
  printf '%s' "${VERSIONS-$VERSIONS_OK}" >"$d/environments/dev/versions.tf"
  printf '%s' "${LOCK-$LOCK_OK}" >"$d/environments/dev/.terraform.lock.hcl"
  cat >"$d/environments/dev/main.tf"
  if [ -n "${EXTRA_FILE:-}" ]; then mkdir -p "$(dirname "$d/$EXTRA_FILE")"; printf '%s' "$EXTRA_BODY" >"$d/$EXTRA_FILE"; fi
  if [ -n "${LINK:-}" ]; then ln -s /etc "$d/$LINK"; fi
  out=$(bash "$guard" "$d" "$allow" 2>&1); rc=$?
  if [ "$rc" -ne "$want" ]; then echo "FAIL $name: expected rc=$want, got rc=$rc: $out"; failures=$((failures + 1)); return; fi
  if ! printf '%s' "$out" | grep -qE "$pattern"; then echo "FAIL $name: right rc, wrong reason: $out"; failures=$((failures + 1)); return; fi
  echo "ok   $name"
}

CLEAN='module "a" {
  source = "../../modules/m"
}
resource "google_storage_bucket" "b" {
  name = "x"
}
resource "google_storage_bucket_object" "o" {
  source = data.archive_file.s.output_path
}
'

run_case clean 0 'ok \(' <<<"$CLEAN"

run_case data_external 1 'main.tf:1: data "external"' <<'EOF'
data "external" "x" { program = ["sh", "-c", "id"] }
EOF
run_case data_http 1 'main.tf:1: data "http"' <<'EOF'
data "http" "x" { url = "https://example.invalid" }
EOF
run_case provider_external 1 'provider "external"' <<'EOF'
provider "external" {}
EOF
run_case provider_http 1 'provider "http"' <<'EOF'
provider "http" {}
EOF
run_case provider_local 1 'provider "local"' <<'EOF'
provider "local" {}
EOF
run_case provider_null 1 'provider "null"' <<'EOF'
provider "null" {}
EOF
# The provider loads with no provider block, so a resource of its type is its own refusal.
run_case resource_null_resource 1 'resource "null_resource"' <<'EOF'
resource "null_resource" "x" {}
EOF
run_case resource_local_file 1 'resource "local_file"' <<'EOF'
resource "local_file" "x" { filename = "a" }
EOF
run_case data_local_file 1 'data "local_file"' <<'EOF'
data "local_file" "x" { filename = "a" }
EOF
run_case provisioner 1 'provisioner blocks' <<'EOF'
resource "google_storage_bucket" "b" {
  provisioner "local-exec" {
    command = "id"
  }
}
EOF
run_case indented_provisioner 1 'main.tf:3: provisioner blocks' <<'EOF'
resource "google_storage_bucket" "b" {
  name = "x"
	provisioner "local-exec" {}
}
EOF
run_case module_git_source 1 'source "git::https://example.invalid/m.git" is neither' <<'EOF'
module "a" {
  source = "git::https://example.invalid/m.git"
}
EOF
run_case module_registry_source 1 'source "terraform-google-modules/network/google" is neither' <<'EOF'
module "a" {
  source = "terraform-google-modules/network/google"
}
EOF
run_case module_github_source 1 'source "github.com/x/y" is neither' <<'EOF'
module "a" {
  source = "github.com/x/y"
}
EOF
run_case module_http_source 1 'is neither' <<'EOF'
module "a" {
  source = "https://example.invalid/m.zip"
}
EOF
run_case spaced_source 1 'is neither' <<'EOF'
module "a" {
  source="git::https://example.invalid/m.git"
}
EOF

# A provider added in required_providers but not in the allowlist.
LOCK="$LOCK_OK" run_case provider_not_allowlisted 1 'source "hashicorp/external" is neither' <<'EOF'
terraform {
  required_providers {
    external = {
      source = "hashicorp/external"
    }
  }
}
EOF
run_case provider_with_host_not_allowlisted 1 'source "registry.terraform.io/hashicorp/http" is neither' <<'EOF'
terraform {
  required_providers {
    http = {
      source = "registry.terraform.io/hashicorp/http"
    }
  }
}
EOF
# The allowlisted provider, spelled with the registry host, is fine.
run_case provider_with_host_allowlisted 0 'ok \(' <<'EOF'
terraform {
  required_providers {
    google = {
      source = "registry.terraform.io/hashicorp/google"
    }
  }
}
EOF

# Lockfile: a provider outside the allowlist, even with clean .tf files.
LOCK='provider "registry.terraform.io/hashicorp/google" {
}
provider "registry.terraform.io/hashicorp/external" {
}
' run_case lockfile_provider 1 'lockfile provider "registry.terraform.io/hashicorp/external" is not in the allowlist' <<<"$CLEAN"

# JSON HCL is not scanned, so it is not accepted.
EXTRA_FILE=environments/dev/extra.tf.json EXTRA_BODY='{"data":{"external":{"x":{"program":["id"]}}}}' \
  run_case tf_json 1 'extra.tf.json: *1|\.tf\.json:1: .tf.json is not accepted|tf.json is not accepted' <<<"$CLEAN"

# Comments are not code: the same words in a comment must NOT refuse (and must not hide a real one below).
run_case comment_is_not_code 0 'ok \(' <<'EOF'
# data "external" "x" {}
// provisioner "local-exec" {}
  # provider "null" {}
resource "google_storage_bucket" "b" {}
EOF
run_case comment_does_not_hide_real_line 1 'main.tf:2: data "external"' <<'EOF'
# data "external" "decoy" {}
data "external" "real" {}
EOF

# ---- R1 (Architect c7084973633): archive_file writes a file at plan time, wherever output_path says. ----
# The real line from modules/billing_killswitch passes (positive control), as does the module-relative spelling.
run_case output_path_real_line_passes 0 'ok \(' <<'EOF'
data "archive_file" "source" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.root}/.terraform/tmp/billing-killswitch-source.zip"
}
EOF
run_case output_path_module_spelling_passes 0 'ok \(' <<'EOF'
data "archive_file" "s" {
  output_path = "${path.module}/.terraform/tmp/a_b-c.1.zip"
}
EOF
run_case output_path_absolute 1 'main.tf:2: output_path must be' <<'EOF'
data "archive_file" "s" {
  output_path = "/home/runner/work/_temp/_runner_file_commands/set_env_x"
}
EOF
run_case output_path_dotdot 1 'output_path must be' <<'EOF'
data "archive_file" "s" {
  output_path = "${path.root}/.terraform/tmp/../../../../x.zip"
}
EOF
run_case output_path_dotdot_as_the_name 1 'output_path must be' <<'EOF'
data "archive_file" "s" {
  output_path = "${path.root}/.terraform/tmp/.."
}
EOF
run_case output_path_dot_as_the_name 1 'output_path must be' <<'EOF'
data "archive_file" "s" {
  output_path = "${path.root}/.terraform/tmp/."
}
EOF
run_case output_path_interpolated_var 1 'output_path must be' <<'EOF'
data "archive_file" "s" {
  output_path = "${path.root}/.terraform/tmp/${var.name}"
}
EOF
run_case output_path_variable_dir 1 'output_path must be' <<'EOF'
data "archive_file" "s" {
  output_path = "${var.dir}/.terraform/tmp/a.zip"
}
EOF
run_case output_path_fileset_path 1 'output_path must be' <<'EOF'
data "archive_file" "s" {
  output_path = tolist(fileset("/home/runner/work/_temp/_runner_file_commands", "set_env_*"))[0]
}
EOF
run_case output_path_non_literal 1 'output_path must be' <<'EOF'
data "archive_file" "s" {
  output_path = local.out
}
EOF
run_case output_path_wrong_dir 1 'output_path must be' <<'EOF'
data "archive_file" "s" {
  output_path = "${path.root}/tmp/a.zip"
}
EOF
run_case output_path_subdir 1 'output_path must be' <<'EOF'
data "archive_file" "s" {
  output_path = "${path.root}/.terraform/tmp/sub/a.zip"
}
EOF
run_case output_path_trailing_text 1 'output_path must be' <<'EOF'
data "archive_file" "s" {
  output_path = "${path.root}/.terraform/tmp/a.zip" # fine
}
EOF
run_case output_path_one_line_block 1 'output_path must be' <<'EOF'
data "archive_file" "s" { type = "zip", output_path = "/etc/cron.d/x" }
EOF
run_case output_path_reading_it_is_fine 0 'ok \(' <<'EOF'
resource "google_storage_bucket_object" "o" {
  source = data.archive_file.source.output_path
}
EOF

# ---- R2: the PR controls the backend block. ----
VERSIONS='terraform {
  backend "http" {
    address = "https://example.invalid/state"
  }
}
' run_case backend_http 1 'backend "http" is not accepted' <<<"$CLEAN"
VERSIONS='terraform {
  cloud {
    organization = "x"
  }
}
' run_case cloud_block 1 'a cloud block is not accepted' <<<"$CLEAN"
# The planned root with NO backend would plan against local state: refused.
VERSIONS='terraform {
  required_providers {
    google = { source = "hashicorp/google" }
  }
}
' run_case root_without_a_backend 1 'exactly one backend "gcs" \(found 0\)' <<<"$CLEAN"
VERSIONS='terraform {
  backend "gcs" {
    prefix = "dev"
  }
  backend "gcs" {
    prefix = "other"
  }
}
' run_case two_gcs_backends_in_the_root 1 'exactly one backend "gcs" \(found 2\)' <<<"$CLEAN"
# A gcs backend that points the token at another host, or at another bucket, or impersonates.
VERSIONS='terraform {
  backend "gcs" {
    prefix                  = "dev"
    storage_custom_endpoint = "https://example.invalid"
  }
}
' run_case gcs_backend_with_an_endpoint 1 'may set only prefix' <<<"$CLEAN"
VERSIONS='terraform {
  backend "gcs" {
    prefix = "dev"
    bucket = "someone-elses"
  }
}
' run_case gcs_backend_with_a_bucket 1 'may set only prefix' <<<"$CLEAN"
VERSIONS='terraform {
  backend "gcs" {
    prefix = "${var.x}"
  }
}
' run_case gcs_backend_prefix_not_a_literal 1 'may set only prefix' <<<"$CLEAN"
VERSIONS='terraform { backend "gcs" { prefix = "dev" } }
' run_case gcs_backend_on_one_line 1 'must open at the end of its line' <<<"$CLEAN"
# A backend (of any type) in a MODULE, and a second root with the wrong type.
EXTRA_FILE=modules/m/main.tf EXTRA_BODY='terraform {
  backend "http" {}
}
' run_case second_backend_in_a_module 1 'modules/m/main.tf:2: backend "http" is not accepted' <<<"$CLEAN"
EXTRA_FILE=modules/m/main.tf EXTRA_BODY='terraform {
  backend "gcs" {
    prefix = "x"
  }
}
' run_case gcs_backend_in_a_module 1 'a backend block in a module is not accepted' <<<"$CLEAN"
EXTRA_FILE=environments/qa/main.tf EXTRA_BODY='terraform {
  backend "http" {}
}
' run_case other_root_with_http_backend 1 'environments/qa/main.tf:2: backend "http" is not accepted' <<<"$CLEAN"
# Positive control: another environment root with a gcs backend (as qa and prod have today) is fine.
EXTRA_FILE=environments/qa/main.tf EXTRA_BODY='terraform {
  backend "gcs" {
    prefix = "qa"
  }
}
' run_case other_root_with_gcs_backend_passes 0 'ok \(' <<<"$CLEAN"
# Backend words in a comment are not code.
VERSIONS='terraform {
  # backend "http" {}
  backend "gcs" {
    # prefix = "x"
    prefix = "dev"
  }
}
' run_case backend_words_in_comments_are_not_code 0 'ok \(' <<<"$CLEAN"

# ---- provider endpoint override, and symbolic links ----
run_case custom_endpoint 1 'main.tf:2: a \*_custom_endpoint attribute' <<'EOF'
provider "google" {
  storage_custom_endpoint = "https://example.invalid/"
}
EOF
LINK=environments/dev/innocent run_case symlink_in_the_tree 1 'innocent: *1|innocent:1: a symbolic link is not accepted|a symbolic link is not accepted' <<<"$CLEAN"
LINK=modules/m/data run_case symlink_in_a_module 1 'a symbolic link is not accepted' <<<"$CLEAN"

# A root that is not in the tree is a usage error, never a pass; a bad root spelling too.
out=$(bash "$guard" "$tmp/clean" "$ALLOW" environments/prod 2>&1); rc=$?
if [ "$rc" = 2 ]; then echo "ok   missing_root_is_an_error"; else echo "FAIL missing_root_is_an_error: rc=$rc $out"; failures=$((failures + 1)); fi
out=$(bash "$guard" "$tmp/clean" "$ALLOW" "../x" 2>&1); rc=$?
if [ "$rc" = 2 ]; then echo "ok   dotdot_root_is_an_error"; else echo "FAIL dotdot_root_is_an_error: rc=$rc $out"; failures=$((failures + 1)); fi

# Fail closed on bad usage.
out=$(bash "$guard" "$tmp/clean" "" 2>&1); rc=$?
if [ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'allowlist is empty'; then echo "ok   empty_allowlist_is_an_error"; else echo "FAIL empty_allowlist_is_an_error: rc=$rc $out"; failures=$((failures + 1)); fi
out=$(bash "$guard" "$tmp/does-not-exist" "$ALLOW" 2>&1); rc=$?
if [ "$rc" = 2 ]; then echo "ok   missing_tree_is_an_error"; else echo "FAIL missing_tree_is_an_error: rc=$rc $out"; failures=$((failures + 1)); fi
out=$(bash "$guard" "$tmp/clean" "hashicorp/google,notaprovider" 2>&1); rc=$?
if [ "$rc" = 2 ]; then echo "ok   malformed_allowlist_entry_is_an_error"; else echo "FAIL malformed_allowlist_entry_is_an_error: rc=$rc $out"; failures=$((failures + 1)); fi

# The live tree passes with the allowlist infra-plan.yml carries (read from the workflow, so the two cannot drift).
live_allow=$(grep -E '^[[:space:]]+PLAN_PROVIDER_ALLOWLIST:' "$repo/.github/workflows/infra-plan.yml" | head -n1 | sed -E "s/^[^:]+:[[:space:]]*//; s/['\"]//g")
if [ -z "$live_allow" ]; then echo "FAIL live_allowlist: infra-plan.yml carries no PLAN_PROVIDER_ALLOWLIST"; failures=$((failures + 1))
else
  out=$(bash "$guard" "$repo" "$live_allow" 2>&1); rc=$?
  if [ "$rc" = 0 ]; then echo "ok   live_tree_passes_the_workflows_allowlist"; else echo "FAIL live_tree: rc=$rc $out"; failures=$((failures + 1)); fi
  # Differential: the lockfiles hold only those providers, and the allowlist is not wider than what they hold.
  held=$(grep -rhoE '^provider "registry.terraform.io/[^"]+"' --include=.terraform.lock.hcl "$repo/environments" "$repo/modules" 2>/dev/null | sed -E 's#^provider "registry.terraform.io/##; s#"$##' | sort -u | tr '\n' ',' | sed 's/,$//')
  want=$(printf '%s' "$live_allow" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
  # Every provider the lockfiles hold must be on the allowlist, or a clean PR would be refused for nothing.
  for p in $(printf '%s' "$held" | tr ',' ' '); do
    case ",$live_allow," in *",$p,"*) ;; *) echo "FAIL allowlist_covers_lockfiles: $p is locked but not allowlisted"; failures=$((failures + 1)) ;; esac
  done
  echo "ok   allowlist_covers_lockfiles (locked: $held; allowlist: $want)"
fi

if [ "$failures" -ne 0 ]; then echo "$failures failure(s)"; exit 1; fi
echo "all check-plan-tree cases passed"
