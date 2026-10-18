#!/usr/bin/env bash
# check-trivyignore.sh — ecofolk-infra#9: every suppression in .trivyignore carries a one-line reason and
# an issue ref. Fails, naming file:line, if:
#   1. a non-comment line is anything but a single check ID (e.g. GCP-0015 or AVD-GCP-0015): no `exp:`,
#      no trailing text, so a suppression can't hide extra fields trivy would act on;
#   2. the line directly above an ID is not a comment;
#   3. that comment has no issue ref (`#N`, or `<name>#N` such as ef#391);
#   4. that comment has no reason: fewer than 10 characters left once the refs are removed.
#   5. an ID appears twice.
# Usage: check-trivyignore.sh [file]   (default .trivyignore)
set -euo pipefail

file="${1:-.trivyignore}"
if [ ! -f "$file" ]; then
  echo "check-trivyignore: $file not found" >&2
  exit 2
fi

fail=0
report() { echo "$file:$1: $2"; fail=1; }

prev=""
n=0
declare -A seen=()
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  trimmed=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  if [ -z "$trimmed" ] || [ "${trimmed:0:1}" = "#" ]; then
    prev="$trimmed"
    continue
  fi

  if ! printf '%s' "$trimmed" | grep -qE '^(AVD-)?[A-Z][A-Z0-9]*-[0-9]{4,}$'; then
    report "$n" "not a single check ID: '$trimmed'"
  fi
  if [ -n "${seen[$trimmed]:-}" ]; then
    report "$n" "$trimmed is already listed at line ${seen[$trimmed]}"
  else
    seen[$trimmed]=$n
  fi

  if [ -z "$prev" ] || [ "${prev:0:1}" != "#" ]; then
    report "$n" "$trimmed has no reason comment on the line above"
  else
    if ! printf '%s' "$prev" | grep -qE '(^|[^[:alnum:]#])[A-Za-z0-9_.-]*#[0-9]+'; then
      report "$n" "the reason above $trimmed has no issue ref (#N)"
    fi
    reason=$(printf '%s' "$prev" | sed -E 's/^#+//; s/[A-Za-z0-9_.-]*#[0-9]+//g; s/[[:space:][:punct:]]+/ /g; s/^ +//; s/ +$//')
    if [ "${#reason}" -lt 10 ]; then
      report "$n" "the comment above $trimmed gives no reason"
    fi
  fi
  prev="$trimmed"
done <"$file"

if [ "$fail" = 1 ]; then
  echo "check-trivyignore: FAILED" >&2
  exit 1
fi
echo "check-trivyignore: ok (${#seen[@]} suppression(s))"
