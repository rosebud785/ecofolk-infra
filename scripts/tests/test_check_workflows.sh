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

run_case rule2_id_token_allowlisted_push_ok pass - infra-apply.yml <<EOF2
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
