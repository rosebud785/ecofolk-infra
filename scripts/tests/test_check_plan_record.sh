#!/usr/bin/env bash
# check-plan-record.sh against a stub `gh` that answers from GitHub-shaped JSON fixtures and applies the script's own
# --jq filters (so the filters are exercised, not bypassed). Each refusal must be refused for the right reason, the
# good path must pass, and a human-authored comment that merely looks like a record must NOT count. A record counts
# only as the LAST line of a github-actions[bot] comment whose FIRST line is one of infra-plan.yml's two headers.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tool="$here/../check-plan-record.sh"
summary="$here/../plan-summary.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa   # the pushed merge commit
HEAD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  # the PR head
TREE=cccccccccccccccccccccccccccccccccccccccc
OTHER=dddddddddddddddddddddddddddddddddddddddd
PLAN_H='### terraform plan (dev) for `bbbbbbbbbbbb`: names only, no values'
STATIC_H='### No PR-time plan for `bbbbbbbbbbbb`'

mkdir -p "$tmp/bin"
# The stub: routes on the API path, applies --jq with jq, reads fixtures from $FIX.
cat >"$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
path="" jq_filter=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    --jq) jq_filter="${args[$((i + 1))]}" ;;
    repos/*) path="${args[$i]}" ;;
  esac
done
case "$path" in
  */commits/*/pulls) f="$FIX/pulls.json" ;;
  */git/commits/*) f="$FIX/commit-${path##*/}.json" ;;
  */issues/*/comments) f="$FIX/comments.json" ;;
  *) echo "stub gh: unrouted $path" >&2; exit 1 ;;
esac
[ -f "$f" ] || { echo "stub gh: no fixture for $path" >&2; exit 1; }
if [ -n "$jq_filter" ]; then jq -r "$jq_filter" "$f"; else cat "$f"; fi
STUB
chmod +x "$tmp/bin/gh"

# A plan, and the hash of it.
cat >"$tmp/plan.json" <<'EOF'
{"resource_changes":[{"address":"google_x.a","change":{"actions":["create"],"before":null,"after":{"n":1},"after_unknown":{}}},
                     {"address":"google_x.b","change":{"actions":["update"],"before":{"n":1},"after":{"n":2},"after_unknown":{}}}]}
EOF
H=$(bash "$summary" hash "$tmp/plan.json")
H2=$(printf 'x' | shasum -a 256 | cut -d' ' -f1)

# comment <login> <body>  -> one comment object
comment() { jq -nc --arg l "$1" --arg b "$2" '{user:{login:$l},body:$b}'; }
# bot <header> <last line>: a well-formed bot comment
bot() { comment "github-actions[bot]" "$(printf '%s\n\nPlan: 1 to add.\n\n%s\n' "$1" "$2")"; }
# comments <comment>...  -> the fixture array
comments() { printf '%s\n' "$@" | jq -s '.' >"$FIX/comments.json"; }

# fresh <name>: a fixture dir in the good shape.
fresh() {
  FIX="$tmp/$1"; mkdir -p "$FIX"
  printf '[{"number":7,"merged_at":"2026-11-22T00:00:00Z","merge_commit_sha":"%s","head":{"sha":"%s"}}]' "$SHA" "$HEAD" >"$FIX/pulls.json"
  printf '{"tree":{"sha":"%s"}}' "$TREE" >"$FIX/commit-$SHA.json"
  printf '{"tree":{"sha":"%s"}}' "$TREE" >"$FIX/commit-$HEAD.json"
  comments "$(bot "$PLAN_H" "plan-record: $HEAD $H")"
  export FIX
}

# expect <name> <rc> <pattern>
expect() {
  local out rc
  out=$(PATH="$tmp/bin:$PATH" GITHUB_REPOSITORY=o/r GITHUB_SHA=$SHA GH_TOKEN=x bash "$tool" "${PLAN:-$tmp/plan.json}" 2>&1); rc=$?
  if [ "$rc" != "$2" ]; then echo "FAIL $1: expected rc=$2, got $rc: $out"; failures=$((failures + 1)); return; fi
  if ! printf '%s' "$out" | grep -qE "$3"; then echo "FAIL $1: right rc, wrong reason: $out"; failures=$((failures + 1)); return; fi
  echo "ok   $1"
}

fresh good;                       expect good_path_passes 0 'plan-record matches: pull request #7'

fresh no_comment;                 printf '[]' >"$FIX/comments.json"
expect no_record_is_refused 1 'no plan-record for its head'

fresh other_head;                 comments "$(bot "$PLAN_H" "plan-record: $OTHER $H")"
expect record_for_another_head_is_refused 1 'no plan-record for its head'

fresh hash_differs;               comments "$(bot "$PLAN_H" "plan-record: $HEAD $H2")"
expect hash_mismatch_is_refused 1 'this plan differs from the plan recorded'

fresh human_forges;               comments "$(comment somebody "$(printf '%s\n\nplan-record: %s %s\n' "$PLAN_H" "$HEAD" "$H")")"
expect a_human_authored_record_does_not_count 1 'no plan-record for its head'

fresh tree_differs;               printf '{"tree":{"sha":"%s"}}' "$OTHER" >"$FIX/commit-$SHA.json"
expect tree_mismatch_is_refused 1 'merged tree is not pull request #7'

fresh no_pr;                      printf '[]' >"$FIX/pulls.json"
expect direct_push_is_refused 1 'no merged pull request has'

fresh unmerged_pr;                printf '[{"number":7,"merged_at":null,"merge_commit_sha":"%s","head":{"sha":"%s"}}]' "$SHA" "$HEAD" >"$FIX/pulls.json"
expect unmerged_pr_does_not_count 1 'no merged pull request has'

fresh pr_with_another_merge_sha;  printf '[{"number":7,"merged_at":"x","merge_commit_sha":"%s","head":{"sha":"%s"}}]' "$OTHER" "$HEAD" >"$FIX/pulls.json"
expect pr_whose_merge_commit_is_another_is_refused 1 'no merged pull request has'

fresh two_prs;                    printf '[{"number":7,"merged_at":"x","merge_commit_sha":"%s","head":{"sha":"%s"}},{"number":8,"merged_at":"x","merge_commit_sha":"%s","head":{"sha":"%s"}}]' "$SHA" "$HEAD" "$SHA" "$OTHER" >"$FIX/pulls.json"
expect two_merged_prs_is_refused 1 'more than one merged pull request'

# The LATEST record wins: an old matching record does not rescue a newer mismatching one, and the reverse.
fresh latest_wins_bad;            comments "$(bot "$PLAN_H" "plan-record: $HEAD $H")" "$(bot "$PLAN_H" "plan-record: $HEAD $H2")"
expect an_older_matching_record_does_not_rescue_a_newer_mismatch 1 'this plan differs'
fresh latest_wins_good;           comments "$(bot "$PLAN_H" "plan-record: $HEAD $H2")" "$(bot "$PLAN_H" "plan-record: $HEAD $H")"
expect a_newer_matching_record_supersedes_an_older_mismatch 0 'plan-record matches'

# static-refused: a PR the plan workflow could not plan applies on its own plan, as before this change.
fresh static_refused;             comments "$(bot "$STATIC_H" "plan-record: $HEAD static-refused")"
expect static_refused_applies_on_its_own_plan 0 'static-refused'
fresh static_refused_by_a_human;  comments "$(comment somebody "$(printf '%s\n\nplan-record: %s static-refused\n' "$STATIC_H" "$HEAD")")"
expect a_human_cannot_waive_the_record 1 'no plan-record for its head'

fresh malformed;                  comments "$(bot "$PLAN_H" "plan-record: $HEAD notahash")"
expect malformed_hash_is_refused 1 'malformed'

# A record whose head only PREFIX-matches must not count (the grep is anchored on the full 40 hex and a space).
fresh prefix;                     comments "$(bot "$PLAN_H" "plan-record: ${HEAD}0 $H")"
expect a_head_prefix_is_not_the_head 1 'no plan-record for its head'

# R4 (Architect c7084973633): the anchoring. Every one of these is a bot comment carrying a perfectly matching
# record line that must still NOT count.
fresh no_header;                  comments "$(comment "github-actions[bot]" "$(printf 'something a future workflow echoes\n\nplan-record: %s %s\n' "$HEAD" "$H")")"
expect a_bot_comment_without_a_header_is_not_a_record 1 'no plan-record for its head'
fresh wrong_header;               comments "$(bot '### terraform plan FAILED for `bbbbbbbbbbbb`' "plan-record: $HEAD $H")"
expect a_bot_comment_with_another_header_is_not_a_record 1 'no plan-record for its head'
fresh header_not_first;           comments "$(comment "github-actions[bot]" "$(printf 'echoed PR text\n%s\n\nplan-record: %s %s\n' "$PLAN_H" "$HEAD" "$H")")"
expect the_header_must_be_the_first_line 1 'no plan-record for its head'
fresh record_not_last;            comments "$(comment "github-actions[bot]" "$(printf '%s\n\nplan-record: %s %s\n\nand more text after it\n' "$PLAN_H" "$HEAD" "$H")")"
expect the_record_must_be_the_last_line 1 'no plan-record for its head'
fresh record_mid_body_header_ok;  comments "$(comment "github-actions[bot]" "$(printf '%s\n\n- `x` add (a)\nplan-record: %s %s\n\nTrailer.\n' "$PLAN_H" "$HEAD" "$H")")"
expect a_record_line_inside_the_body_is_not_a_record 1 'no plan-record for its head'
# The header on its own is not enough: the last line must be the record for THIS head.
fresh header_last_line_other;     comments "$(bot "$PLAN_H" "Plan: nothing")"
expect a_header_without_a_record_is_not_a_record 1 'no plan-record for its head'
# CRLF bodies (a client that converts newlines) still anchor correctly.
fresh crlf;                       comments "$(comment "github-actions[bot]" "$(printf '%s\r\n\r\nplan-record: %s %s\r\n' "$PLAN_H" "$HEAD" "$H")")"
expect a_crlf_body_is_still_a_record 0 'plan-record matches'

# An API error is a refusal, never a pass.
fresh api_error;                  rm -f "$FIX/pulls.json"
expect an_api_error_is_a_refusal 1 'could not read the pull requests'

# Differential: the same good fixture with ONE tree byte changed flips pass -> refuse (the control moves the result).
fresh differential;               expect differential_before_the_change 0 'matches'
printf '{"tree":{"sha":"%s"}}' "$OTHER" >"$FIX/commit-$HEAD.json"
expect differential_after_the_change 1 'merged tree is not'

# Bad usage.
out=$(PATH="$tmp/bin:$PATH" GITHUB_REPOSITORY=o/r GITHUB_SHA=short bash "$tool" "$tmp/plan.json" 2>&1); rc=$?
[ "$rc" = 2 ] && echo "ok   bad_sha_is_a_usage_error" || { echo "FAIL bad_sha_is_a_usage_error: rc=$rc $out"; failures=$((failures + 1)); }
out=$(PATH="$tmp/bin:$PATH" GITHUB_REPOSITORY=o/r GITHUB_SHA=$SHA bash "$tool" "$tmp/nope.json" 2>&1); rc=$?
[ "$rc" = 2 ] && echo "ok   missing_plan_is_a_usage_error" || { echo "FAIL missing_plan_is_a_usage_error: rc=$rc $out"; failures=$((failures + 1)); }

if [ "$failures" -ne 0 ]; then echo "$failures failure(s)"; exit 1; fi
echo "all check-plan-record cases passed"
