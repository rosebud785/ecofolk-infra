#!/usr/bin/env bash
# Known-bad fixture per rule (each must fail, naming the rule) plus a clean one (must pass).
# Fixtures live in a temp dir, never as live workflows.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
guard="$here/../check-workflows.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

SHA=0123456789abcdef0123456789abcdef01234567
failures=0

# case <name> <expect: pass|fail> <grep pattern the output must match, or -> <workflow filename> <body on stdin>
run_case() {
  local name=$1 expect=$2 pattern=$3 file=$4
  local d="$tmp/$name"
  mkdir -p "$d"
  cat >"$d/$file"
  local out rc
  out=$(bash "$guard" "$d" 2>&1)
  rc=$?
  if [ "$expect" = pass ]; then
    if [ $rc -ne 0 ]; then echo "FAIL $name: expected pass, got rc=$rc: $out"; failures=$((failures + 1)); return; fi
  else
    if [ $rc -eq 0 ]; then echo "FAIL $name: expected failure, guard passed"; failures=$((failures + 1)); return; fi
    if ! printf '%s' "$out" | grep -qE "$pattern"; then echo "FAIL $name: failed but not for the right reason: $out"; failures=$((failures + 1)); return; fi
    if ! printf '%s' "$out" | grep -qE "$file:[0-9]+:"; then echo "FAIL $name: output does not name file:line: $out"; failures=$((failures + 1)); return; fi
  fi
  echo "ok   $name"
}

run_case clean pass - ci.yml <<EOF2
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA # v4
      - uses: ./.github/actions/local
      - run: echo "\${{ github.token }}"
EOF2

run_case rule1_pull_request_target fail 'pull_request_target' bad1.yml <<EOF2
on:
  pull_request_target:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule2_id_token_on_pr fail 'id-token: write in a workflow triggered by pull_request' bad2.yml <<EOF2
on:
  pull_request:
permissions:
  id-token: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule2_id_token_outside_allowlist fail 'outside the allowlist' bad2b.yml <<EOF2
on:
  push:
    branches: [main]
permissions:
  id-token: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule2_id_token_allowlisted_push_job_level_ok pass - infra-apply.yml <<EOF2
on:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule2_id_token_job_level_outside_allowlist fail 'outside the allowlist' bad2c.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule2_id_token_allowlisted_name_but_pr fail 'triggered by pull_request' infra-apply.yml <<EOF2
on: [pull_request]
permissions:
  id-token: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

# ecofolk-infra#162: infra-plan.yml is allowlisted for a guarded workflow_dispatch, and ONLY for that.
run_case rule2_infra_plan_dispatch_on_main_ok pass - infra-plan.yml <<EOF2
on:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  a:
    if: github.ref == 'refs/heads/main' && github.ref_protected
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule2_infra_plan_with_pull_request_trigger fail 'triggered by pull_request' infra-plan.yml <<EOF2
on:
  workflow_dispatch:
  pull_request:
permissions:
  contents: read
jobs:
  a:
    if: github.ref == 'refs/heads/main' && github.ref_protected
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule2_infra_plan_dispatch_without_guard fail 'without an .if: github.ref' infra-plan.yml <<EOF2
on:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@$SHA
EOF2

# The same trigger on a not-allowlisted name is still refused (the allowlist, not the trigger, is the first gate).
run_case rule2_plan_like_name_outside_allowlist fail 'outside the allowlist' infra-plan-extra.yml <<EOF2
on:
  workflow_dispatch:
jobs:
  a:
    if: github.ref == 'refs/heads/main' && github.ref_protected
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule3_secret_on_pr fail 'secrets\.\* referenced' bad3.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo
        env:
          T: \${{ secrets.DEPLOY_KEY }}
EOF2

run_case rule3_secret_on_push_ok pass - ok3.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo "\${{ secrets.DEPLOY_KEY }}"
EOF2

run_case rule4_unpinned_tag fail 'not pinned to a 40-hex SHA' bad4.yml <<EOF2
on:
  push:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF2

run_case rule4_unpinned_branch fail 'not pinned to a 40-hex SHA' bad4b.yml <<EOF2
on:
  push:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@main # 0123456789abcdef0123456789abcdef01234567
EOF2

# ecofolk-infra#31 -- the permissions rules read the PARSED workflow. One known-wrong per evasion.
run_case rule5_workflow_level_id_token_in_allowlisted_file fail 'id-token: write at workflow level' infra-apply.yml <<EOF2
on:
  push:
    branches: [main]
permissions:
  id-token: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_write_all_workflow_level fail 'write-all' bad5a.yml <<EOF2
on:
  push:
permissions: write-all
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_write_all_job_level fail 'write-all' bad5b.yml <<EOF2
on:
  push:
jobs:
  a:
    runs-on: ubuntu-latest
    permissions: write-all
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_quoted_key_double fail 'id-token: write' bad5c.yml <<EOF2
on:
  push:
permissions:
  "id-token": write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_quoted_key_and_value_single fail 'id-token: write' bad5d.yml <<EOF2
on:
  push:
jobs:
  a:
    runs-on: ubuntu-latest
    permissions:
      'id-token': 'write'
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_alias_value fail 'id-token: write' bad5e.yml <<EOF2
on:
  push:
x-w: &w write
jobs:
  a:
    runs-on: ubuntu-latest
    permissions:
      id-token: *w
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_alias_whole_permissions fail 'id-token: write' bad5f.yml <<EOF2
on:
  push:
x-p: &p
  id-token: write
jobs:
  a:
    runs-on: ubuntu-latest
    permissions: *p
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_merge_key fail 'id-token: write' bad5g.yml <<EOF2
on:
  push:
x-p: &p
  id-token: write
jobs:
  a:
    runs-on: ubuntu-latest
    permissions:
      <<: *p
      contents: read
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_flow_style_mapping fail 'id-token: write' bad5h.yml <<EOF2
on:
  push:
jobs:
  a:
    runs-on: ubuntu-latest
    permissions: { contents: read, id-token: write }
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_pr_write_permission fail 'triggered by pull_request \(read or none only\)' bad5i.yml <<EOF2
on:
  pull_request:
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_pr_job_level_pull_requests_write fail 'pull-requests: write' bad5j.yml <<EOF2
on: [pull_request]
jobs:
  a:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_pr_review_workflow_write fail 'triggered by pull_request_review \(read or none only\)' bad5r1.yml <<EOF2
on: pull_request_review
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_pr_review_comment_job_write fail 'triggered by pull_request_review_comment \(read or none only\)' bad5r2.yml <<EOF2
on:
  pull_request_review_comment:
    types: [created]
jobs:
  a:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_pr_review_list_with_push_write fail 'triggered by pull_request_review \(read or none only\)' bad5r3.yml <<EOF2
on:
  push:
    branches: [main]
  pull_request_review:
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_pr_review_read_ok pass - ok5r.yml <<EOF2
on: pull_request_review
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case allow_issue_comment_write fail 'triggered by issue_comment \(read or none only\)' bad6a.yml <<EOF2
on: issue_comment
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case allow_workflow_run_secret fail 'secrets\.\* referenced in a workflow triggered by workflow_run' bad6b.yml <<EOF2
on:
  workflow_run:
    workflows: [ci]
    types: [completed]
env:
  T: \${{ secrets.DEPLOY_KEY }}
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case allow_mixed_list_write fail 'triggered by issue_comment \(read or none only\)' bad6c.yml <<EOF2
on:
  push:
    branches: [main]
  issue_comment:
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case allow_unknown_trigger_write fail 'triggered by some_future_event \(read or none only\)' bad6d.yml <<EOF2
on: some_future_event
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case allow_review_secret fail 'secrets\.\* referenced in a workflow triggered by pull_request_review' bad6e.yml <<EOF2
on: pull_request_review
env:
  T: \${{ secrets.DEPLOY_KEY }}
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case allow_no_on_fails_closed fail 'triggered by <no on:>' bad6f.yml <<EOF2
name: x
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case allow_schedule_write_ok pass '-' ok6a.yml <<EOF2
on:
  schedule:
    - cron: '0 3 * * *'
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case allow_dispatch_and_push_write_ok pass '-' ok6b.yml <<EOF2
on:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: write
jobs:
  a:
    if: github.ref == 'refs/heads/main' && github.ref_protected
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_push_no_branches_write fail 'triggered by push \(not limited to branches: \[main\]\)' bad7a.yml <<EOF2
on: push
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_push_wildcard_write fail 'triggered by push \(not limited' bad7b.yml <<EOF2
on:
  push:
    branches: ['**']
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_push_feature_branch_write fail 'triggered by push \(not limited' bad7c.yml <<EOF2
on:
  push:
    branches: ['feature/*']
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_push_branches_ignore_write fail 'triggered by push \(not limited' bad7d.yml <<EOF2
on:
  push:
    branches: [main]
    branches-ignore: [x]
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_push_tags_write fail 'triggered by push \(not limited' bad7e.yml <<EOF2
on:
  push:
    branches: [main]
    tags: ['v*']
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_push_bare_secret fail 'secrets\.\* referenced in a workflow triggered by push \(not limited' bad7f.yml <<EOF2
on: push
env:
  T: \${{ secrets.DEPLOY_KEY }}
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_write_no_guard fail 'triggered by workflow_dispatch \(job a is privileged' bad7g.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_secret_no_guard fail 'secrets\.\* referenced in a workflow triggered by workflow_dispatch \(job a' bad7h.yml <<EOF2
on: workflow_dispatch
env:
  T: \${{ secrets.DEPLOY_KEY }}
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_guard_with_or_fails fail 'workflow_dispatch \(job a is privileged' bad7i.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: write
jobs:
  a:
    if: github.ref == 'refs/heads/main' || github.actor == 'x'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_negated_guard_fails fail 'workflow_dispatch \(job a is privileged' bad8a.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: write
jobs:
  a:
    if: "!(github.ref == 'refs/heads/main')"
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_not_equal_fails fail 'workflow_dispatch \(job a is privileged' bad8b.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: write
jobs:
  a:
    if: github.ref != 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_guard_and_not_cancelled_fails_closed fail 'workflow_dispatch \(job a is privileged' bad8c.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: write
jobs:
  a:
    if: github.ref == 'refs/heads/main' && !cancelled()
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_secrets_inherit_no_guard fail 'secrets: inherit' bad8d.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: read
jobs:
  a:
    uses: acme/repo/.github/workflows/x.yml@$SHA
    secrets: inherit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_secrets_mapping_no_guard fail 'workflow_dispatch \(job a is privileged' bad8e.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: read
jobs:
  a:
    uses: acme/repo/.github/workflows/x.yml@$SHA
    secrets:
      K: literal
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_wrapped_guard_and_term_ok pass '-' ok8a.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: write
jobs:
  a:
    if: \${{ github.ref == 'refs/heads/main' && github.ref_protected && github.actor == 'x' }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_secrets_inherit_guarded_ok pass '-' ok8b.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: read
env:
  TF_DIR: environments/dev   # rule 5: a reusable-workflow call must come with proof of a dev target
jobs:
  a:
    if: github.ref == 'refs/heads/main' && github.ref_protected
    uses: acme/repo/.github/workflows/x.yml@$SHA
    secrets: inherit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_push_string_branch_ok pass '-' ok7a.yml <<EOF2
on:
  push:
    branches: main
permissions:
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_guarded_write_ok pass '-' ok7b.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: write
jobs:
  a:
    if: github.ref == 'refs/heads/main' && github.ref_protected
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_guarded_secret_ok pass '-' ok7c.yml <<EOF2
on: workflow_dispatch
env:
  T: \${{ secrets.DEPLOY_KEY }}
jobs:
  a:
    if: github.ref == 'refs/heads/main' && github.ref_protected
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_read_only_ok pass '-' ok7d.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule3_secrets_bracket_single fail 'secrets\.\* referenced in a workflow triggered by pull_request' bad9a.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo "\${{ secrets['DEPLOY_KEY'] }}"
EOF2

run_case rule3_secrets_bracket_double fail 'secrets\.\* referenced in a workflow triggered by pull_request' bad9b.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo '\${{ secrets["DEPLOY_KEY"] }}'
EOF2

run_case rule3_secrets_tojson fail 'secrets\.\* referenced in a workflow triggered by pull_request' bad9c.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo '\${{ toJson(secrets) }}'
EOF2

run_case rule3_secrets_tojson_upper fail 'secrets\.\* referenced in a workflow triggered by pull_request' bad9d.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo '\${{ toJSON(secrets) }}'
EOF2

run_case rule3_secrets_in_format fail 'secrets\.\* referenced in a workflow triggered by pull_request' bad9e.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo "\${{ format('{0}', secrets.DEPLOY_KEY) }}"
EOF2

run_case rule3_secrets_multiline_expression fail 'secrets\.\* referenced in a workflow triggered by pull_request' bad9f.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: |
          echo "\${{
            secrets.DEPLOY_KEY
          }}"
EOF2

run_case rule3_secrets_github_token_spelling_fails fail 'secrets\.\* referenced in a workflow triggered by pull_request' bad9g.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo "\${{ secrets.GITHUB_TOKEN }}"
EOF2

run_case rule3_secrets_in_if_condition fail 'secrets\.\* referenced in a workflow triggered by pull_request' bad9h.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - if: \${{ secrets.DEPLOY_KEY != '' }}
        run: echo hi
EOF2

run_case rule3_secrets_mixed_case_dot fail 'secrets\.\* referenced in a workflow triggered by' bad9i.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo "\${{ Secrets.K }}"
EOF2

run_case rule3_secrets_upper_bracket fail 'secrets\.\* referenced in a workflow triggered by' bad9j.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo "\${{ SECRETS['K'] }}"
EOF2

run_case rule3_secrets_mixed_case_tojson fail 'secrets\.\* referenced in a workflow triggered by' bad9k.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo '\${{ toJson(SeCrEtS) }}'
EOF2

run_case rule3_dispatch_unguarded_mixed_case fail 'secrets\.\* referenced in a workflow triggered by' bad9l.yml <<EOF2
on: workflow_dispatch
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo "\${{ Secrets.K }}"
EOF2

run_case rule3_hash_inside_quoted_scalar_does_not_hide fail 'secrets\.\* referenced in a workflow triggered by pull_request' bad9m.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: 'echo "build #1 \${{ secrets.DEPLOY_KEY }}"'
EOF2

run_case rule3_shell_comment_in_block_scalar_does_not_hide fail 'secrets\.\* referenced in a workflow triggered by pull_request' bad9n.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: |
          echo hi # \${{ secrets.DEPLOY_KEY }}
EOF2

run_case rule3_hash_before_expression_in_block fail 'secrets\.\* referenced in a workflow triggered by pull_request' bad9o.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: |
          # \${{ secrets.DEPLOY_KEY }}
          echo hi
EOF2

run_case rule3_real_yaml_comment_after_value_ok pass '-' ok9d.yml <<EOF2
on:
  pull_request:
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo hi # \${{ secrets.DEPLOY_KEY }}
EOF2

run_case rule3_job_secrets_inherit_hash_string_fail fail 'secrets: passed to job a' bad9p.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    uses: acme/repo/.github/workflows/x.yml@$SHA
    secrets: inherit
EOF2

run_case rule3_secrets_commented_out_ok pass '-' ok9a.yml <<EOF2
on:
  pull_request:
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      # \${{ secrets.DEPLOY_KEY }} would be bad
      - run: echo hi
EOF2

run_case rule3_secrets_word_outside_expression_ok pass '-' ok9b.yml <<EOF2
on:
  pull_request:
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo 'no secrets here'
EOF2

run_case rule3_github_token_spelling_ok pass '-' ok9c.yml <<EOF2
on:
  pull_request:
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
      - run: echo "\${{ github.token }}"
EOF2

run_case rule5_pr_alias_write fail 'pull_request' bad5k.yml <<EOF2
on:
  pull_request:
x-p: &p
  contents: write
permissions: *p
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_pr_read_and_none_ok pass - ok5b.yml <<EOF2
on:
  pull_request:
permissions:
  contents: read
  pull-requests: none
jobs:
  a:
    runs-on: ubuntu-latest
    permissions: read-all
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_push_write_permission_ok pass - ok5c.yml <<EOF2
on:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule5_unparseable_workflow_fails fail 'parse failure' bad5l.yml <<EOF2
on:
  push:
jobs:
  a: [unclosed
EOF2

run_case rule5_tabs_unparseable_fails fail 'parse failure' bad5m.yml <<EOF2
on: push
jobs:
	a: {}
EOF2

run_case rule5_non_mapping_fails fail 'not a YAML mapping' bad5n.yml <<EOF2
- just
- a list
EOF2

# Rule 5 (#12): no workflow plans or applies environments/prod. CI only validates it.
run_case prod_plan_chdir fail 'CI only validates prod' prod1.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: terraform -chdir=environments/prod plan -no-color
EOF2

run_case prod_apply_working_directory fail 'CI only validates prod' prod2.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - name: Apply
        working-directory: environments/prod
        run: terraform apply -auto-approve
EOF2

run_case prod_via_env_var fail 'CI only validates prod' prod3.yml <<EOF2
on:
  push:
    branches: [main]
env:
  TF_DIR: environments/prod
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - working-directory: \${{ env.TF_DIR }}
        run: |
          terraform init
          terraform plan -out=tfplan
EOF2

run_case prod_via_glob_loop fail 'CI only validates prod' prod4.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: |
          for d in environments/*; do
            terraform -chdir="\$d" apply -auto-approve
          done
EOF2

run_case prod_via_runtime_path fail 'CI only validates prod' prod5.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - working-directory: environments/\${{ vars.TARGET_ENV }}
        run: terraform plan
EOF2

run_case prod_apply_action fail 'CI only validates prod' prod6.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: example/terraform-apply@$SHA # v1
        with:
          path: environments/prod
EOF2

run_case prod_tofu_plan fail 'CI only validates prod' prod7.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: tofu -chdir=environments/prod plan
EOF2

run_case prod_validate_only_ok pass - prodok1.yml <<EOF2
on:
  pull_request:
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: |
          for d in environments/*; do
            terraform -chdir="\$d" init -backend=false -input=false
            terraform -chdir="\$d" validate
          done
EOF2

run_case prod_dev_apply_with_paths_filter_ok pass - prodok2.yml <<EOF2
on:
  push:
    branches: [main]
    paths:
      - 'environments/**'
      - 'environments/prod/**'
env:
  TF_DIR: environments/dev
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      # never plan or apply environments/prod here
      - working-directory: \${{ env.TF_DIR }}
        run: |
          terraform plan -detailed-exitcode -out=tfplan
          terraform apply -auto-approve tfplan
EOF2

# Positive proof of dev (Architect c7112003379): a near-miss of dev is NOT dev. Was an ok fixture under the
# prod denylist; under the allowlist it fails closed.
run_case prod_not_dev_prefix_fails fail 'CI only validates prod' prodok3.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: terraform -chdir=environments/production-like-dev plan
EOF2

# Known-wrong corpus for the redesign: each of these passed at a4db560a (Architect probes + ef-qa HOLD).
bypass() { # name, step-yaml (indented under `steps:`)
  run_case "bypass_$1" fail 'CI only validates prod' "bp_$1.yml" <<EOF3
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
$2
EOF3
}
bypass continuation "      - run: |
          terraform -chdir=environments/prod \\\\
            plan -no-color"
bypass double_slash "      - run: terraform -chdir=environments//prod plan"
bypass dot_segment "      - run: terraform -chdir=environments/./prod plan"
bypass quoted_segment "      - run: terraform -chdir=environments/\"prod\" plan"
bypass glob_segment "      - run: terraform -chdir=environments/p* plan"
bypass parent_dir_chdir "      - working-directory: environments
        run: terraform -chdir=prod plan"
bypass whole_path_from_var "      - run: terraform -chdir=\${{ vars.TF_DIR }} plan"
bypass quoted_terraform "      - run: \"terraform\" -chdir=environments/prod plan"
bypass quoted_apply "      - run: terraform -chdir=environments/prod 'apply'"
bypass quoted_hash_before_apply "      - run: |
          echo \"x #\" ; terraform -chdir=environments/prod apply"
bypass not_dev_literal "      - run: terraform plan"

run_case bypass_reusable_caller fail 'CI only validates prod' bp_reuse_caller.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    uses: ./.github/workflows/tf.yml
    with:
      dir: environments/prod
EOF2

run_case bypass_reusable_callee fail 'CI only validates prod' bp_reuse_callee.yml <<EOF2
on:
  workflow_call:
    inputs:
      dir:
        type: string
        required: true
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: terraform -chdir=\${{ inputs.dir }} apply
EOF2

run_case bypass_dispatch_input_default fail 'CI only validates prod' bp_dispatch_input.yml <<EOF2
on:
  workflow_dispatch:
    inputs:
      dir:
        type: choice
        default: environments/prod
        options: [environments/dev, environments/prod]
env:
  TF_DIR: environments/dev
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: terraform -chdir=\$TF_DIR plan
EOF2

run_case bypass_matrix_env fail 'CI only validates prod' bp_matrix.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    strategy:
      matrix:
        env: [dev, prod]
    runs-on: ubuntu-latest
    steps:
      - run: terraform -chdir=environments/\${{ matrix.env }} plan
EOF2

run_case dev_continuation_ok pass - bp_dev_cont.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: |
          terraform -chdir=environments/dev \\\\
            plan -no-color
EOF2

# Scalar walk (Architect note on #84): a `#` inside a quoted scalar is content, not a comment, and a prod path
# only in a real YAML comment is not named.
run_case prod_after_hash_in_quoted_scalar fail 'CI only validates prod' prod8.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: "echo '#' ; terraform -chdir=environments/prod plan"
EOF2

run_case prod_only_in_comment_ok pass - prodok4.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      # never plan or apply environments/prod here
      - run: terraform -chdir=environments/dev plan
EOF2

# Per-step dev target + text segments (Architect addenda c7112080858 C and c7112113044 D').
# stepcase NAME fail|pass STEP_YAML [WORKFLOW_ENV_YAML]  (steps indented 6, env lines indented 2)
stepcase() {
  local exp="$2" msg="CI only validates prod"; [ "$2" = pass ] && msg="-"
  run_case "$1" "$exp" "$msg" "sc_$1.yml" <<EOF3
on:
  push:
    branches: [main]
${4:+env:
$4}
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
$3
EOF3
}
# N1/N2: a literal dev named elsewhere must not vouch for a step whose directory is an expression.
stepcase n1_inputs_dir fail '      - run: terraform -chdir=${{ inputs.dir }} apply' '  DEV_DIR: environments/dev'
stepcase n2_vars_dir fail '      - run: terraform -chdir=${{ vars.TF_DIR }} apply' '  DEV_DIR: environments/dev'
# N3: a run-time rewrite of a dev path is the stated residual (passes).
stepcase n3_runtime_rewrite pass '      - run: |
          TF_DIR="${TF_DIR%dev}prod"
          terraform -chdir="$TF_DIR" apply' '  TF_DIR: environments/dev'
# N4: the allowed indirections.
stepcase n4_env_chdir pass '      - run: terraform -chdir="$TF_DIR" apply' '  TF_DIR: environments/dev'
stepcase n4b_env_working_directory pass '      - working-directory: ${{ env.TF_DIR }}
        run: terraform apply' '  TF_DIR: environments/dev'
stepcase n4c_prefix_checkout pass '      - working-directory: pr/${{ env.TF_DIR }}
        run: terraform plan' '  TF_DIR: environments/dev'
stepcase n4d_braced pass '      - run: terraform -chdir=${TF_DIR} plan' '  TF_DIR: environments/dev'
stepcase n5_env_value_is_expression fail '      - run: terraform -chdir="$TF_DIR" apply' '  TF_DIR: ${{ vars.X }}/environments/dev
  DEV: environments/dev'
stepcase n6_dotdot_prefix fail '      - working-directory: ../environments/dev
        run: terraform apply'
# E1/E2: text that mentions a command is not a command.
stepcase e1_validate_or_echo pass '      - run: terraform validate || { echo "::error::terraform plan failed"; exit 1; }'
stepcase e2_echo_mentions_apply pass '      - run: echo "terraform apply on environments/prod is never run from CI"'
stepcase e3_whole_line_comment pass '      - run: |
          # terraform apply is not run here
          true'
# C1-C7: wrappers around the command still count.
stepcase c1_env_prefix fail '      - run: env TF_LOG=INFO terraform -chdir=environments/prod apply'
stepcase c2_var_assignment fail '      - run: TF_LOG=INFO terraform -chdir=environments/prod apply'
stepcase c3_true_and fail '      - run: true && terraform -chdir=environments/prod apply'
stepcase c4_if fail '      - run: if terraform -chdir=environments/prod apply; then echo ok; fi'
stepcase c5_time_command fail '      - run: time command terraform -chdir=environments/prod apply'
stepcase c6_command_subst fail '      - run: x=$(terraform -chdir=environments/prod apply)'
stepcase c7_pipe fail '      - run: terraform -chdir=environments/prod apply | tee out.txt'
# X1-X5 (ef-qa): an echo/printf/`:` that wraps a running command is still a running command.
stepcase x1_echo_subst fail '      - run: echo "$(terraform -chdir=environments/prod apply)"'
stepcase x2_printf_subst fail '      - run: printf "%s" "$(terraform -chdir=environments/prod apply)"'
stepcase x3_colon_subst fail '      - run: : "$(terraform -chdir=environments/prod apply)"'
stepcase x4_echo_backtick fail '      - run: echo `terraform -chdir=environments/prod apply`'
stepcase x5_echo_and fail '      - run: echo x && terraform -chdir=environments/prod apply'
stepcase t1_terragrunt_apply_prod fail '      - run: terragrunt -chdir=environments/prod apply'
stepcase t2_terragrunt_run_all fail '      - run: terragrunt run-all apply'
stepcase t3_terragrunt_dev_ok pass '      - run: terragrunt -chdir=environments/dev plan'
stepcase d1_dev_still_passes pass '      - run: terraform -chdir=environments/dev plan'

# The live workflows must pass (infra-apply.yml is job-level only and push-triggered).
live=$(cd "$here/../.." && bash scripts/check-workflows.sh .github/workflows 2>&1) \
  && echo "ok   live_workflows_pass" || { echo "FAIL live_workflows_pass: $live"; failures=$((failures + 1)); }

run_case comment_mentions_do_not_count pass - ok5.yml <<EOF2
# pull_request_target would be bad; id-token: write too
on:
  push:
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA # v4 not pull_request
EOF2

# --- #65: a PR-triggered workflow with no permissions block gets the repo default token ---------------------

run_case rule6_pr_no_permissions_block fail 'has no permissions: block' bad65a.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule6_pr_one_job_missing_permissions fail 'job b has no permissions: block' bad65b.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@$SHA
  b:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule6_pr_every_job_has_permissions_ok pass - ok65a.yml <<EOF2
on:
  pull_request:
jobs:
  a:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@$SHA
  b:
    runs-on: ubuntu-latest
    permissions: {}
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule6_pr_empty_workflow_permissions_ok pass - ok65b.yml <<EOF2
on:
  pull_request:
permissions: {}
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule6_trusted_push_main_without_permissions_ok pass - ok65c.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

# --- #65: duplicate keys inside a permissions mapping (YAML keeps the last) --------------------------------

run_case rule7_duplicate_key_workflow_level fail "duplicate key 'contents' in permissions" bad65c.yml <<EOF2
on:
  pull_request:
permissions:
  contents: write
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule7_duplicate_key_job_level_on_push fail "duplicate key 'contents' in permissions at job a" bad65d.yml <<EOF2
on:
  push:
    branches: [main]
jobs:
  a:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      contents: write
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule7_duplicate_key_via_merge fail "duplicate key 'contents' in permissions" bad65e.yml <<EOF2
on:
  push:
    branches: [main]
base: &base
  contents: read
permissions:
  <<: *base
  contents: write
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule7_distinct_keys_ok pass - ok65d.yml <<EOF2
on:
  pull_request:
permissions:
  contents: read
  pull-requests: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

# --- #82: GitHub's == is case-insensitive, so the ref guard alone is satisfied by a branch named `Main` -----

run_case rule8_ref_guard_without_ref_protected fail 'privileged without an' bad82a.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: write
jobs:
  a:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule8_ref_guard_with_unrelated_term_only fail 'privileged without an' bad82b.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: write
jobs:
  a:
    if: github.ref == 'refs/heads/main' && github.actor == 'x'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule8_ref_protected_alone_is_not_the_main_guard fail 'privileged without an' bad82c.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: write
jobs:
  a:
    if: github.ref_protected
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case rule8_ref_protected_equals_true_ok pass - ok82a.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: write
jobs:
  a:
    if: github.ref == 'refs/heads/main' && github.ref_protected == true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

if [ $failures -ne 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all check-workflows cases passed"
