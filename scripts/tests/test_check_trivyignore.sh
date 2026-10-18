#!/usr/bin/env bash
# Known-bad fixture per rule of check-trivyignore.sh (each must fail, naming the rule and file:line) plus
# clean ones (must pass). Fixtures live in a temp dir, never as the live .trivyignore.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
guard="$here/../check-trivyignore.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0

# run_case <name> <expect: pass|fail> <grep pattern the output must match, or -> <body on stdin>
run_case() {
  local name=$1 expect=$2 pattern=$3
  local f="$tmp/$name.trivyignore"
  cat >"$f"
  local out rc
  out=$(bash "$guard" "$f" 2>&1)
  rc=$?
  if [ "$expect" = pass ]; then
    if [ $rc -ne 0 ]; then echo "FAIL $name: expected pass, got rc=$rc: $out"; failures=$((failures + 1)); return; fi
  else
    if [ $rc -eq 0 ]; then echo "FAIL $name: expected failure, guard passed"; failures=$((failures + 1)); return; fi
    if ! printf '%s' "$out" | grep -qE "$pattern"; then echo "FAIL $name: failed but not for the right reason: $out"; failures=$((failures + 1)); return; fi
    if ! printf '%s' "$out" | grep -qE "$name.trivyignore:[0-9]+:"; then echo "FAIL $name: output does not name file:line: $out"; failures=$((failures + 1)); return; fi
  fi
  echo "ok   $name"
}

run_case clean pass - <<'EOF'
# Header comments are free text.

# modules/cloudsql: waiting on the app's TLS setting (#9).
GCP-0015
# The AVD- prefix is accepted, and a cross-repo ref like ef#391 counts.
AVD-GCP-0016
EOF

run_case empty pass - </dev/null

run_case no_trailing_newline pass - < <(printf '# a reason long enough (#9)\nGCP-0015')

run_case rule1_trailing_text fail 'not a single check ID' <<'EOF'
# a reason long enough (#9)
GCP-0015 exp:2099-01-01
EOF

run_case rule1_not_an_id fail 'not a single check ID' <<'EOF'
# a reason long enough (#9)
modules/cloudsql/main.tf
EOF

run_case rule2_no_comment fail 'no reason comment' <<'EOF'
GCP-0015
EOF

run_case rule2_blank_line_between fail 'no reason comment' <<'EOF'
# a reason long enough (#9)

GCP-0015
EOF

run_case rule2_reason_shared_by_two fail 'no reason comment' <<'EOF'
# a reason long enough (#9)
GCP-0015
GCP-0016
EOF

run_case rule3_no_issue_ref fail 'no issue ref' <<'EOF'
# a reason long enough but no ref
GCP-0015
EOF

run_case rule3_hash_without_number fail 'no issue ref' <<'EOF'
# a reason long enough, see # above
GCP-0015
EOF

run_case rule4_ref_only fail 'gives no reason' <<'EOF'
# (#9)
GCP-0015
EOF

run_case rule5_duplicate fail 'already listed' <<'EOF'
# a reason long enough (#9)
GCP-0015
# a second reason long enough (#9)
GCP-0015
EOF

if out=$(bash "$guard" "$tmp/does-not-exist" 2>&1); then
  echo "FAIL missing_file: expected failure"; failures=$((failures + 1))
else
  echo "ok   missing_file"
fi

if [ "$failures" -ne 0 ]; then
  echo "test_check_trivyignore: $failures failure(s)" >&2
  exit 1
fi
echo "test_check_trivyignore: all cases ok"
