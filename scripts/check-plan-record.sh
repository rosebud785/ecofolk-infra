#!/usr/bin/env bash
# check-plan-record.sh — ecofolk-infra#162 (Architect ruling c7084664707), the refuse-on-diff of infra-apply.yml.
# A plan with changes may apply only if the plan a reviewer could read on the merged PR (infra-plan.yml's
# `plan-record` comment, posted by github-actions[bot]) is the plan computed HERE. Every failure below applies nothing
# (the workflow stops on a non-zero exit, and the red run is the page); recovery is a fresh infra-plan dispatch on the
# PR's head, then a re-run of the apply.
#   * no merged PR for this commit, or more than one (a direct push to main applies nothing);
#   * the merge commit's tree is not the PR head's tree (strict "up to date" protection gives equality; a PR merged
#     behind main would apply code nobody planned);
#   * no plan-record comment for that head sha, or its hash is not the hash of this plan.
# Exception: a PR whose tree infra-plan.yml REFUSED statically (a data source or provider that runs code at plan time)
# has the record `plan-record: <head> static-refused`: nobody could read a plan, and the apply's own plan is the first
# one, as before this change. The LATEST record for the head wins, so a re-dispatch supersedes an older one.
#
# Usage: check-plan-record.sh <plan.json>      (terraform show -json of the saved apply plan)
# Env:   GITHUB_REPOSITORY, GITHUB_SHA (the pushed merge commit), GH_TOKEN; `gh` on PATH.
# Exit:  0 the reviewed plan is this plan (or static-refused); 1 REFUSED (names why); 2 bad usage.
# Surface path (CODEOWNERS): weakening this needs ARCHITECT APPROVED.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plan="${1:-}"
repo="${GITHUB_REPOSITORY:-}"
sha="${GITHUB_SHA:-}"
[ -r "$plan" ] || { echo "check-plan-record: plan json '$plan' not readable" >&2; exit 2; }
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "check-plan-record: GITHUB_REPOSITORY is not owner/name" >&2; exit 2; }
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "check-plan-record: GITHUB_SHA is not 40 lowercase hex" >&2; exit 2; }

die() { echo "::error::REFUSED (nothing applied): $*"; exit 1; }

mine="$(bash "$here/plan-summary.sh" hash "$plan")" || die "could not summarise this plan"
[[ "$mine" =~ ^[0-9a-f]{64}$ ]] || die "this plan's hash is not a sha256"

prs="$(gh api "repos/$repo/commits/$sha/pulls" \
  --jq ".[] | select(.merged_at != null and .merge_commit_sha == \"$sha\") | [.number, .head.sha] | @tsv")" \
  || die "could not read the pull requests for $sha"
[ -n "$prs" ] || die "no merged pull request has $sha as its merge commit (a direct push to main applies nothing)"
[ "$(printf '%s\n' "$prs" | grep -c .)" = 1 ] || die "more than one merged pull request claims $sha"
IFS=$'\t' read -r pr head <<<"$prs"
[[ "$pr" =~ ^[0-9]+$ ]] || die "the merged pull request number is not a number"
[[ "$head" =~ ^[0-9a-f]{40}$ ]] || die "pull request #$pr has no usable head sha"

merge_tree="$(gh api "repos/$repo/git/commits/$sha" --jq .tree.sha)" || die "could not read the merge commit"
head_tree="$(gh api "repos/$repo/git/commits/$head" --jq .tree.sha)" || die "could not read pull request #$pr's head commit"
[ -n "$merge_tree" ] && [ "$merge_tree" = "$head_tree" ] \
  || die "the merged tree is not pull request #$pr's head tree: the plan that was reviewed is not this code"

# A record is the LAST line of a comment by github-actions[bot] whose FIRST line is one of infra-plan.yml's two headers
# (R4, Architect c7084973633). A record line anywhere else in a bot comment (a future workflow that echoes PR text, say)
# is not a record. Whole-body CRs and trailing newlines are normalised first.
comments="$(gh api --paginate "repos/$repo/issues/$pr/comments" \
  --jq '.[] | select(.user.login == "github-actions[bot]")
        | (.body | gsub("\r"; "") | rtrimstr("\n") | split("\n")) as $l
        | select(($l[0] | startswith("### terraform plan (dev) for ")) or ($l[0] | startswith("### No PR-time plan for ")))
        | $l[-1]')" || die "could not read pull request #$pr's comments"
latest="$(printf '%s\n' "$comments" | grep -E "^plan-record: $head " | tail -n1 || true)"
[ -n "$latest" ] || die "pull request #$pr has no plan-record for its head $head (run infra-plan.yml on it, then re-run this apply)"
rec="${latest##* }"
if [ "$rec" = static-refused ]; then
  echo "plan-record: $head static-refused. No PR-time plan could be run on this tree; this apply's own plan is the first one."
  exit 0
fi
[[ "$rec" =~ ^[0-9a-f]{64}$ ]] || die "the plan-record for $head is malformed"
[ "$rec" = "$mine" ] || die "this plan differs from the plan recorded for pull request #$pr's head (recorded ${rec:0:12}, this plan ${mine:0:12}): infra changed since the plan was read, re-run infra-plan.yml"
echo "plan-record matches: pull request #$pr, head $head, plan ${mine:0:12}"
