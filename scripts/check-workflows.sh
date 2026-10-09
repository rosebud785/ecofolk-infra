#!/usr/bin/env bash
# Makes "no credentials on a PR path" mechanical. Fails, naming file:line, if any workflow:
#   1. contains pull_request_target;
#   2. has `id-token: write` while triggered by pull_request, or in any file not on the allowlist below;
#   3. references secrets.* (other than secrets.GITHUB_TOKEN) while triggered by pull_request;
#   4. has a `uses:` not pinned to a 40-hex SHA (local ./ actions are exempt).
# Usage: check-workflows.sh [workflow-dir]   (default .github/workflows)
# Surface path (CODEOWNERS): weakening this needs ARCHITECT APPROVED.
set -euo pipefail

dir="${1:-.github/workflows}"
# The only workflows allowed to hold id-token: write (and so to obtain WIF credentials). Added by ef#883.
ALLOW_ID_TOKEN=(infra-apply.yml)

fail=0
report() { echo "$1:$2: $3"; fail=1; }

shopt -s nullglob
files=("$dir"/*.yml "$dir"/*.yaml)
if [ ${#files[@]} -eq 0 ]; then
  echo "check-workflows: no workflow files in $dir" >&2
  exit 1
fi

for f in "${files[@]}"; do
  base=$(basename "$f")
  # Comments stripped (line numbers preserved) so a `# pull_request` remark or a `# v4` tag never counts.
  stripped=$(sed -E 's/(^|[[:space:]])#.*$//' "$f")

  # 1. pull_request_target
  while IFS=: read -r n _; do
    report "$f" "$n" "pull_request_target is forbidden"
  done < <(printf '%s\n' "$stripped" | grep -nE 'pull_request_target' || true)

  # Triggered by pull_request? (the bare word, not pull_request_target / pull_request_review)
  on_pr=0
  if printf '%s\n' "$stripped" | grep -qE '(^|[^A-Za-z_])pull_request([^A-Za-z_]|$)'; then on_pr=1; fi

  # 2. id-token: write
  while IFS=: read -r n _; do
    allowed=0
    for a in "${ALLOW_ID_TOKEN[@]}"; do [ "$base" = "$a" ] && allowed=1; done
    if [ "$on_pr" = 1 ]; then
      report "$f" "$n" "id-token: write in a workflow triggered by pull_request"
    elif [ "$allowed" = 0 ]; then
      report "$f" "$n" "id-token: write outside the allowlist (${ALLOW_ID_TOKEN[*]})"
    fi
  done < <(printf '%s\n' "$stripped" | grep -nE 'id-token:[[:space:]]*write' || true)

  # 3. secrets.* on a PR path
  if [ "$on_pr" = 1 ]; then
    while IFS=: read -r n _; do
      report "$f" "$n" "secrets.* referenced in a workflow triggered by pull_request"
    done < <(printf '%s\n' "$stripped" | grep -nE 'secrets\.[A-Za-z_]' | grep -vE 'secrets\.GITHUB_TOKEN' || true)
    while IFS=: read -r n _; do
      report "$f" "$n" "secrets: inherit / secrets context in a workflow triggered by pull_request"
    done < <(printf '%s\n' "$stripped" | grep -nE 'secrets:[[:space:]]*inherit|toJSON\(secrets\)' || true)
  fi

  # 4. unpinned uses:
  while IFS=: read -r n rest; do
    ref=$(printf '%s' "$rest" | sed -E 's/^[[:space:]-]*uses:[[:space:]]*//; s/["'"'"']//g; s/[[:space:]]+$//')
    case "$ref" in
      ./*) continue ;;
      docker://*@sha256:*) continue ;;
    esac
    if ! printf '%s' "$ref" | grep -qE '@[0-9a-f]{40}$'; then
      report "$f" "$n" "uses: '$ref' is not pinned to a 40-hex SHA"
    fi
  done < <(printf '%s\n' "$stripped" | grep -nE '^[[:space:]-]*uses:' || true)
done

if [ "$fail" = 1 ]; then
  echo "check-workflows: FAILED" >&2
  exit 1
fi
echo "check-workflows: ok (${#files[@]} file(s))"
