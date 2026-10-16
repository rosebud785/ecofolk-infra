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
      - run: echo "\${{ secrets.GITHUB_TOKEN }}"
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
