#!/usr/bin/env bash
# Makes "no credentials on a PR path" mechanical. Fails, naming file:line, if any workflow:
#   1. contains pull_request_target;
#   2. permissions, on the PARSED workflow (check-workflow-permissions.py): an untrusted-trigger workflow with no
#      permissions block at workflow level or on a job (#65); a duplicate key inside a permissions mapping (#65);
#      `write-all` anywhere; `id-token: write`
#      at workflow level, in an untrusted-trigger workflow, or in a job of a file not on the allowlist below; any
#      permission other than read/none in an untrusted-trigger workflow; a workflow that does not parse;
#   3. has `secrets` anywhere inside a ${{ }} expression (any spelling; check-workflow-permissions.py) or
#      `secrets: inherit`, in a workflow with any untrusted trigger (trusted =
#      push limited to branches: [main], schedule, and workflow_dispatch whose privileged jobs carry
#      `if: github.ref == 'refs/heads/main' && github.ref_protected` (== is case-insensitive, #82); see check-workflow-permissions.py);
#   4. has a `uses:` not pinned to a 40-hex SHA (local ./ actions are exempt);
#   5. could plan or apply anything but environments/dev (ecofolk-infra#88, #12, pipeline design §6.2: CI only
#      validates prod, it never plans or applies it). POSITIVE PROOF per step, not a prod denylist
#      (`check-workflow-permissions.py --tf-violations`, on the PARSED scalars):
#      - capable = a `terraform`/`tofu`/`terragrunt` word with plan or apply after it, in a segment (the scalar with
#        `\`-newline joined and quote characters removed, split on newline ; && || | $( and backticks) that is
#        not TEXT. A segment is text only if, after leading VAR=value assignments, it starts with echo, printf
#        or `:`, or it is a whole-line comment. Everything else counts (env, if, time, command, sudo, heredoc
#        bodies...): over-detects, never misses. A `uses:` action named plan/apply and any job-level
#        reusable-workflow call are capable too, and need the whole workflow to prove dev.
#      - each capable segment's directory comes from its `-chdir=`, else the step's `working-directory`, else
#        the job's, else the workflow's `defaults.run.working-directory`; no source = unsafe. It must resolve
#        to [<prefix>/]environments/dev (then end or `/`; the prefix a fixed relative path, no `..`, no
#        expression). The only indirection is ${{ env.X }}, $X or ${X} with X a literal in an env map (step,
#        job, workflow; nearest wins). Any other expression (inputs, vars, matrix, needs...) is unsafe.
#      - and EVERY `environments/` anywhere (the trigger's `on:` inputs included, its `paths:` filters
#        excluded) must be exactly environments/dev: aliases (`//`, `./`, quotes, globs) fail.
#      Dev only; qa stays out until a reviewed change adds it.
#      THE PROD BOUNDARY IS THE IDENTITY, NOT THIS RULE: dev trusts pin `gcp-dev` (apply_ok, deploy_ok) and
#      prod's SA trust (#165 §D) requires `gcp-prod` + Andy's reviewer. STATED RESIDUAL (this rule reads
#      workflow text): a wrapper script that targets prod internally (`./deploy.sh`); a run-time `cd` out
#      of, or a rewrite of, the named dev directory (`TF_DIR="${TF_DIR%dev}prod"`); a subcommand assembled
#      from variables (`ACTION: apply` ... `terraform "$ACTION"`). Defence in depth, same bar as #188: the
#      obvious and idiomatic forms are caught, the rest is stated, not chased.
# Usage: check-workflows.sh [workflow-dir]   (default .github/workflows)
# Surface path (CODEOWNERS): weakening this needs ARCHITECT APPROVED.
set -euo pipefail

dir="${1:-.github/workflows}"
# The only workflows allowed to hold id-token: write (and so to obtain WIF credentials). Added by ef#883.
# infra-plan.yml (ecofolk-infra#162, Architect ruling c7084664707): workflow_dispatch on protected main only; a
# pull_request trigger on a workflow that holds id-token is refused by rule 2 whatever the file is called.
ALLOW_ID_TOKEN=(infra-apply.yml deploy-app.yml infra-plan.yml)

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

  # 3. `secrets: inherit` in an untrusted workflow (the expression form is checked by the python rule)
  if [ "$on_pr" = 1 ]; then
    while IFS=: read -r n _; do
      report "$f" "$n" "secrets: inherit / secrets context in a workflow triggered by $trig"
    done < <(printf '%s\n' "$stripped" | grep -nE 'secrets:[[:space:]]*inherit' || true)
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

  # 5. plan/apply that could reach environments/prod (#88)
  # Positive proof of a dev target PER plan/apply-capable step (--tf-violations, on the parsed scalars): each
  # one that cannot prove it is reported at file:line.
  py="$(dirname "${BASH_SOURCE[0]}")/check-workflow-permissions.py"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    report "$f" "$n" "plan/apply-capable line that does not prove an environments/dev target; CI only validates prod (#12, #88)"
  done < <(python3 -I "$py" --tf-violations "$f")
done

if [ "$fail" = 1 ]; then
  echo "check-workflows: FAILED" >&2
  exit 1
fi
echo "check-workflows: ok (${#files[@]} file(s))"
