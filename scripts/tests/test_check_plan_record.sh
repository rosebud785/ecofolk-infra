#!/usr/bin/env bash
# check-plan-record.sh against a stub `gh` that answers from GitHub-shaped JSON fixtures and applies the script's own
# --jq filters (so the filters are exercised, not bypassed). Each refusal must be refused for the right reason, the
# good path must pass, and a human-authored comment that merely looks like a record must NOT count.
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
H2=$(printf 'x' | sha256sum 2>/dev/null | cut -d' ' -f1 || printf 'x' | shasum -a 256 | cut -d' ' -f1)

# fresh <name>: a fixture dir in the good shape.
fresh() {
  FIX="$tmp/$1"; mkdir -p "$FIX"
  printf '[{"number":7,"merged_at":"2026-11-22T00:00:00Z","merge_commit_sha":"%s","head":{"sha":"%s"}}]' "$SHA" "$HEAD" >"$FIX/pulls.json"
  printf '{"tree":{"sha":"%s"}}' "$TREE" >"$FIX/commit-$SHA.json"
  printf '{"tree":{"sha":"%s"}}' "$TREE" >"$FIX/commit-$HEAD.json"
  printf '[{"user":{"login":"github-actions[bot]"},"body":"### terraform plan\\n\\nplan-record: %s %s"}]' "$HEAD" "$H" >"$FIX/comments.json"
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

fresh other_head;                 printf '[{"user":{"login":"github-actions[bot]"},"body":"plan-record: %s %s"}]' "$OTHER" "$H" >"$FIX/comments.json"
expect record_for_another_head_is_refused 1 'no plan-record for its head'

fresh hash_differs;               printf '[{"user":{"login":"github-actions[bot]"},"body":"plan-record: %s %s"}]' "$HEAD" "$H2" >"$FIX/comments.json"
expect hash_mismatch_is_refused 1 'this plan differs from the plan recorded'

fresh human_forges;               printf '[{"user":{"login":"somebody"},"body":"plan-record: %s %s"}]' "$HEAD" "$H" >"$FIX/comments.json"
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
fresh latest_wins_bad;            printf '[{"user":{"login":"github-actions[bot]"},"body":"plan-record: %s %s"},{"user":{"login":"github-actions[bot]"},"body":"plan-record: %s %s"}]' "$HEAD" "$H" "$HEAD" "$H2" >"$FIX/comments.json"
expect an_older_matching_record_does_not_rescue_a_newer_mismatch 1 'this plan differs'
fresh latest_wins_good;           printf '[{"user":{"login":"github-actions[bot]"},"body":"plan-record: %s %s"},{"user":{"login":"github-actions[bot]"},"body":"plan-record: %s %s"}]' "$HEAD" "$H2" "$HEAD" "$H" >"$FIX/comments.json"
expect a_newer_matching_record_supersedes_an_older_mismatch 0 'plan-record matches'

# static-refused: a PR the plan workflow could not plan applies on its own plan, as before this change.
fresh static_refused;             printf '[{"user":{"login":"github-actions[bot]"},"body":"x\\nplan-record: %s static-refused"}]' "$HEAD" >"$FIX/comments.json"
expect static_refused_applies_on_its_own_plan 0 'static-refused'
fresh static_refused_by_a_human;  printf '[{"user":{"login":"somebody"},"body":"plan-record: %s static-refused"}]' "$HEAD" >"$FIX/comments.json"
expect a_human_cannot_waive_the_record 1 'no plan-record for its head'

fresh malformed;                  printf '[{"user":{"login":"github-actions[bot]"},"body":"plan-record: %s notahash"}]' "$HEAD" >"$FIX/comments.json"
expect malformed_hash_is_refused 1 'malformed'

# A record whose head only PREFIX-matches must not count (the grep is anchored on the full 40 hex and a space).
fresh prefix;                     printf '[{"user":{"login":"github-actions[bot]"},"body":"plan-record: %s0 %s"}]' "$HEAD" "$H" >"$FIX/comments.json"
expect a_head_prefix_is_not_the_head 1 'no plan-record for its head'

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
