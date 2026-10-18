#!/usr/bin/env bash
# Makes "no credentials on a PR path" mechanical. Fails, naming file:line, if any workflow:
#   1. contains pull_request_target;
#   2. permissions, on the PARSED workflow (check-workflow-permissions.py): `write-all` anywhere; `id-token: write`
#      at workflow level, in an untrusted-trigger workflow, or in a job of a file not on the allowlist below; any
#      permission other than read/none in an untrusted-trigger workflow; a workflow that does not parse;
#   3. references secrets.* (other than secrets.GITHUB_TOKEN) in a workflow with any untrusted trigger (trusted =
#      push limited to branches: [main], schedule, and workflow_dispatch whose privileged jobs carry
#      `if: github.ref == 'refs/heads/main'`; see check-workflow-permissions.py);
#   4. has a `uses:` not pinned to a 40-hex SHA (local ./ actions are exempt);
#   5. could run `plan` or `apply` in environments/prod (ecofolk-infra#12, pipeline design §6.2: CI only
#      validates prod, it never plans or applies it). A workflow fails, at each plan/apply line, if it both
#      runs plan/apply (a `terraform`/`tofu` command line naming plan or apply, or a `uses:` action whose
#      name contains plan or apply) and names a directory that is or could be prod: `environments/prod`,
#      an `environments/*` glob, or an `environments/$...` path built at run time, anywhere outside `on:`
#      (check-workflow-permissions.py --names-prod). Fails closed: a workflow
#      that applies dev must name environments/dev literally, as infra-apply.yml does.
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

# 2. permissions (ecofolk-infra#31): parsed, not grepped, so anchors / merge keys / flow style / quoted keys
# cannot hide a write. Rules are in check-workflow-permissions.py's header. A parse failure fails the guard.
if ! command -v python3 >/dev/null 2>&1 || ! python3 -I -c 'import yaml' 2>/dev/null; then
  echo "check-workflows: python3 with PyYAML is required (the permissions rules parse the workflow)" >&2
  exit 1
fi
allow_csv=$(IFS=,; echo "${ALLOW_ID_TOKEN[*]}")
set +e
perm_out=$(python3 -I "$(dirname "${BASH_SOURCE[0]}")/check-workflow-permissions.py" "$allow_csv" "${files[@]}")
perm_rc=$?
set -e
if [ "$perm_rc" -ne 0 ]; then
  printf '%s\n' "$perm_out"
  fail=1
fi

for f in "${files[@]}"; do
  base=$(basename "$f")
  # Comments stripped (line numbers preserved) so a `# pull_request` remark or a `# v4` tag never counts.
  stripped=$(sed -E 's/(^|[[:space:]])#.*$//' "$f")

  # 1. pull_request_target
  while IFS=: read -r n _; do
    report "$f" "$n" "pull_request_target is forbidden"
  done < <(printf '%s\n' "$stripped" | grep -nE 'pull_request_target' || true)

  # Untrusted trigger? One definition shared with rule 2 (check-workflow-permissions.py TRUSTED_TRIGGERS:
  # push-to-main, schedule and ref-guarded workflow_dispatch are trusted; anything else, unknown included, is not).
  trig=$(python3 -I "$(dirname "${BASH_SOURCE[0]}")/check-workflow-permissions.py" --trigger "$f")
  on_pr=0
  if [ "$trig" != "trusted" ]; then on_pr=1; fi

  # 3. secrets.* in a workflow with an untrusted trigger
  if [ "$on_pr" = 1 ]; then
    while IFS=: read -r n _; do
      report "$f" "$n" "secrets.* referenced in a workflow triggered by $trig"
    done < <(printf '%s\n' "$stripped" | grep -nE 'secrets\.[A-Za-z_]' | grep -vE 'secrets\.GITHUB_TOKEN' || true)
    while IFS=: read -r n _; do
      report "$f" "$n" "secrets: inherit / secrets context in a workflow triggered by $trig"
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

  # 5. plan/apply that could reach environments/prod (#12)
  # Whether the workflow names prod is asked of the parser (outside `on:`, whose `paths:` filters are not
  # directories a step runs in); the plan/apply lines are grepped so each is reported at file:line.
  if [ "$(python3 -I "$(dirname "${BASH_SOURCE[0]}")/check-workflow-permissions.py" --names-prod "$f")" = prod ]; then
    while IFS=: read -r n _; do
      report "$f" "$n" "plan/apply in a workflow that names environments/prod (or a glob/run-time path that can reach it); CI only validates prod (#12)"
    done < <(printf '%s\n' "$stripped" | grep -nE '(^|[^A-Za-z0-9_-])(terraform|tofu)([[:space:]].*)?[[:space:]](plan|apply)([^A-Za-z0-9_-]|$)|^[[:space:]-]*uses:[^@]*(plan|apply)' || true)
  fi
done

if [ "$fail" = 1 ]; then
  echo "check-workflows: FAILED" >&2
  exit 1
fi
echo "check-workflows: ok (${#files[@]} file(s))"
