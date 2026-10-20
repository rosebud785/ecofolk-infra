#!/usr/bin/env bash
# Known-wrong fixtures for check-dependabot-majors.sh (each must fail for the right reason), clean ones (must
# pass), and the live .github/dependabot.yml (must pass). Fixtures live in a temp dir.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
guard="$here/../check-dependabot-majors.sh"
live="$here/../../.github/dependabot.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

# run_case <name> <expected rc> <pattern the output must match> <  yaml on stdin>
run_case() {
  local name=$1 want=$2 pattern=$3 f="$tmp/$1.yml" out rc
  cat >"$f"
  out=$(bash "$guard" "$f" 2>&1); rc=$?
  if [ "$rc" -ne "$want" ]; then echo "FAIL $name: expected rc=$want, got rc=$rc: $out"; failures=$((failures + 1)); return; fi
  if ! printf '%s' "$out" | grep -qE "$pattern"; then echo "FAIL $name: right rc, wrong reason: $out"; failures=$((failures + 1)); return; fi
  echo "ok   $name"
}

run_case good 0 'ok \(1 terraform entry' <<'Y'
version: 2
updates:
  - package-ecosystem: terraform
    directory: /
    ignore:
      - dependency-name: '*'
        update-types: ['version-update:semver-major']
  - package-ecosystem: github-actions
    directory: /
Y

run_case no_ignore_block 1 'updates\[0\] \(terraform\) does not ignore semver-major' <<'Y'
version: 2
updates:
  - package-ecosystem: terraform
    directory: /
Y

run_case ignores_only_minor 1 'does not ignore semver-major' <<'Y'
version: 2
updates:
  - package-ecosystem: terraform
    directory: /
    ignore:
      - dependency-name: '*'
        update-types: ['version-update:semver-minor']
Y

run_case ignores_one_named_dependency_only 1 'does not ignore semver-major' <<'Y'
version: 2
updates:
  - package-ecosystem: terraform
    directory: /
    ignore:
      - dependency-name: 'hashicorp/google'
        update-types: ['version-update:semver-major']
Y

run_case ignore_on_the_wrong_ecosystem 1 'updates\[0\] \(terraform\)' <<'Y'
version: 2
updates:
  - package-ecosystem: terraform
    directory: /
  - package-ecosystem: github-actions
    directory: /
    ignore:
      - dependency-name: '*'
        update-types: ['version-update:semver-major']
Y

run_case second_terraform_entry_unprotected 1 'updates\[1\] \(terraform\)' <<'Y'
version: 2
updates:
  - package-ecosystem: terraform
    directory: /a
    ignore:
      - dependency-name: '*'
        update-types: ['version-update:semver-major']
  - package-ecosystem: terraform
    directory: /b
Y

run_case no_terraform_entry_fails_closed 2 'no terraform ecosystem entry' <<'Y'
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
Y

run_case unparseable_fails_closed 2 'does not parse' <<'Y'
version: 2
updates: [unclosed
Y

# Coverage (Architect, #124): every dir holding a versions.tf must be listed. Fixture repo roots with the
# yml passed explicitly alongside the root.
mkroot() { rm -rf "$tmp/root"; mkdir -p "$tmp/root/modules/a" "$tmp/root/modules/b" "$tmp/root/environments/dev" \
  "$tmp/root/modules/a/.terraform/x" "$tmp/root/.git"
  : >"$tmp/root/modules/a/versions.tf"; : >"$tmp/root/modules/b/versions.tf"; : >"$tmp/root/environments/dev/versions.tf"
  : >"$tmp/root/modules/a/.terraform/x/versions.tf"; }   # the .terraform copy must NOT count
cover_case() {  # cover_case <name> <expected rc> <pattern> <  yaml on stdin>
  local name=$1 want=$2 pattern=$3 f="$tmp/$1.yml" out rc
  cat >"$f"; mkroot
  out=$(bash "$guard" "$f" "$tmp/root" 2>&1); rc=$?
  if [ "$rc" -ne "$want" ]; then echo "FAIL $name: expected rc=$want, got rc=$rc: $out"; failures=$((failures + 1)); return; fi
  if ! printf '%s' "$out" | grep -qE "$pattern"; then echo "FAIL $name: right rc, wrong reason: $out"; failures=$((failures + 1)); return; fi
  echo "ok   $name"
}
cover_case coverage_all_listed_control 0 'ok \(1 terraform entry ignore semver-major; 3 versions.tf dir' <<'Y'
version: 2
updates:
  - package-ecosystem: terraform
    directories: [/environments/dev, /modules/a, /modules/b]
    ignore:
      - dependency-name: '*'
        update-types: ['version-update:semver-major']
Y
cover_case coverage_glob_counts 0 '3 versions.tf dir' <<'Y'
version: 2
updates:
  - package-ecosystem: terraform
    directories: [/environments/dev, '/modules/*']
    ignore:
      - dependency-name: '*'
        update-types: ['version-update:semver-major']
Y
cover_case coverage_unlisted_module_fails 1 '/modules/b holds a versions.tf but is not in any terraform entry' <<'Y'
version: 2
updates:
  - package-ecosystem: terraform
    directories: [/environments/dev, /modules/a]
    ignore:
      - dependency-name: '*'
        update-types: ['version-update:semver-major']
Y

if out=$(bash "$guard" "$tmp/missing.yml" 2>&1); then echo "FAIL missing_file: expected failure"; failures=$((failures + 1)); else echo "ok   missing_file"; fi

if out=$(bash "$guard" "$live" 2>&1); then echo "ok   live_dependabot_yml: $out"; else echo "FAIL live_dependabot_yml: $out"; failures=$((failures + 1)); fi

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
echo "all cases passed"
