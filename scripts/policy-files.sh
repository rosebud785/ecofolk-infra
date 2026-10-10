#!/usr/bin/env bash
# Prints the files the conftest policy (policy/, ecofolk-infra#7) must read: every tracked *.tf in the
# repo, at any depth, one per line, sorted. A local module or a top-level local-only/ outside
# environments/ and modules/ is still Terraform, so it is still scanned.
#
# Fails if any *.tf.json is tracked: Terraform loads JSON configuration too, but the hcl2 parser never
# sees it, so it would bypass the policy.
#
# Usage: policy-files.sh [repo-dir]   (default .)
# Surface path: the policy job's input. Narrowing it weakens every rule in policy/.
set -euo pipefail

dir="${1:-.}"

mapfile -t json < <(git -C "$dir" -c core.quotePath=false ls-files -- '*.tf.json')
if [ ${#json[@]} -gt 0 ]; then
  for f in "${json[@]}"; do
    echo "$f: JSON Terraform isn't policy-checked; write HCL" >&2
  done
  exit 1
fi

mapfile -t files < <(git -C "$dir" -c core.quotePath=false ls-files -- '*.tf' | sort)
if [ ${#files[@]} -eq 0 ]; then
  echo "policy-files: no tracked *.tf files in $dir" >&2
  exit 1
fi
printf '%s\n' "${files[@]}"
