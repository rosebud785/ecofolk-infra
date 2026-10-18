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
    if: github.ref == 'refs/heads/main'
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
    if: \${{ github.ref == 'refs/heads/main' && github.actor == 'x' }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA
EOF2

run_case main_dispatch_secrets_inherit_guarded_ok pass '-' ok8b.yml <<EOF2
on: workflow_dispatch
permissions:
  contents: read
jobs:
  a:
    if: github.ref == 'refs/heads/main'
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
    if: github.ref == 'refs/heads/main'
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
    if: github.ref == 'refs/heads/main'
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

run_case rule3_secrets_commented_out_ok pass '-' ok9a.yml <<EOF2
on:
  pull_request:
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

# The live workflows must pass (infra-apply.yml is job-level only and push-triggered).
live=$(cd "$here/../.." && bash scripts/check-workflows.sh .github/workflows 2>&1) \
  && echo "ok   live_workflows_pass" || { echo "FAIL live_workflows_pass: $live"; failures=$((failures + 1)); }

run_case comment_mentions_do_not_count pass - ok5.yml <<EOF2
# pull_request_target would be bad; id-token: write too
on:
  push:
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@$SHA # v4 not pull_request
EOF2

if [ $failures -ne 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all check-workflows cases passed"
