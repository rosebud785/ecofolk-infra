#!/usr/bin/env bash
# plan-summary.sh: the comment is NAMES ONLY (a planted secret value never appears), destroy/replace are called out,
# the hash moves when an address or action moves and does NOT move when only a value moves, order does not matter,
# a no-op/read-only entry does not count, and a non-plan input is an error (never "No resource changes").
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tool="$here/../plan-summary.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
HEAD=0123456789abcdef0123456789abcdef01234567
SECRET='s3cr3t-VALUE-must-never-print'

ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; failures=$((failures + 1)); }

# Plan with: an add (a sensitive value in after), an update (a value changes), a replace, a destroy, a no-op, a read.
cat >"$tmp/plan.json" <<EOF
{"resource_changes":[
 {"address":"google_secret_manager_secret.new","change":{"actions":["create"],"before":null,"after":{"secret_id":"x","payload":"$SECRET","labels":{"a":"b"}},"after_unknown":{"id":true}}},
 {"address":"google_cloud_run_v2_service.api","change":{"actions":["update"],"before":{"image":"old","name":"api"},"after":{"image":"$SECRET","name":"api"},"after_unknown":{}}},
 {"address":"google_sql_database_instance.db","change":{"actions":["delete","create"],"before":{"tier":"a"},"after":{"tier":"b"},"after_unknown":{}}},
 {"address":"google_pubsub_topic.gone","change":{"actions":["delete"],"before":{"name":"t"},"after":null,"after_unknown":{}}},
 {"address":"google_project.p","change":{"actions":["no-op"],"before":{"a":1},"after":{"a":1},"after_unknown":{}}},
 {"address":"data.google_client_config.c","change":{"actions":["read"],"before":null,"after":{"z":1},"after_unknown":{}}}
]}
EOF

out=$(bash "$tool" comment "$tmp/plan.json" "$HEAD" 2>&1); rc=$?
[ "$rc" = 0 ] && ok comment_runs || bad "comment_runs: rc=$rc $out"
printf '%s' "$out" | grep -qF "$SECRET" && bad "a secret VALUE reached the comment" || ok no_value_in_comment
printf '%s' "$out" | grep -q 'DESTROY / REPLACE: 1 destroy, 1 replace' && ok destroy_and_replace_called_out_at_the_top || bad "no destroy/replace callout: $out"
printf '%s' "$out" | grep -q 'Plan: 1 to add, 1 to change, 1 to destroy, 1 to replace' && ok counts || bad "counts wrong: $out"
printf '%s' "$out" | grep -q '`google_cloud_run_v2_service.api` change (image)' && ok changed_attribute_named_not_valued || bad "update line wrong: $out"
printf '%s' "$out" | grep -q 'google_secret_manager_secret.new` add (' && ok add_listed || bad "add line wrong: $out"
printf '%s' "$out" | grep -q 'google_project.p' && bad "a no-op resource is listed" || ok no_op_not_listed
printf '%s' "$out" | grep -q 'data.google_client_config' && bad "a read-only entry is listed" || ok read_not_listed
# Replace sorts before destroy before the rest.
r=$(printf '%s' "$out" | grep -n 'sql_database_instance' | cut -d: -f1); d=$(printf '%s' "$out" | grep -n 'pubsub_topic.gone' | cut -d: -f1); a=$(printf '%s' "$out" | grep -n 'cloud_run_v2_service' | cut -d: -f1)
[ "$r" -lt "$d" ] && [ "$d" -lt "$a" ] && ok replace_then_destroy_then_rest || bad "order wrong: $r $d $a"
last=$(printf '%s\n' "$out" | tail -n1)
rec=$(bash "$tool" record "$tmp/plan.json" "$HEAD")
[ "$last" = "$rec" ] && printf '%s' "$rec" | grep -qE "^plan-record: $HEAD [0-9a-f]{64}$" && ok record_is_the_last_line || bad "record line: '$last' vs '$rec'"

# The hash: stable under reordering, and under a changed VALUE; it moves on an address or an action.
h0=$(bash "$tool" hash "$tmp/plan.json")
jq '.resource_changes |= reverse' "$tmp/plan.json" >"$tmp/reordered.json"
[ "$(bash "$tool" hash "$tmp/reordered.json")" = "$h0" ] && ok hash_ignores_order || bad hash_ignores_order
jq '(.resource_changes[] | select(.address=="google_cloud_run_v2_service.api") | .change.after.image) = "another"' "$tmp/plan.json" >"$tmp/value.json"
[ "$(bash "$tool" hash "$tmp/value.json")" = "$h0" ] && ok hash_ignores_values || bad hash_ignores_values
# R3 (Architect c7084973633): same resource and same action, a DIFFERENT set of changed attribute names, is a different
# hash (console drift between the plan and the merge that updates other attributes must not match). Identical plans
# are identical, and a value-only change (same names) stays equal (hash_ignores_values above).
jq '(.resource_changes[] | select(.address=="google_cloud_run_v2_service.api") | .change) |= (.before.timeout = "30s" | .after.timeout = "60s")' "$tmp/plan.json" >"$tmp/names.json"
[ "$(bash "$tool" hash "$tmp/names.json")" != "$h0" ] && ok hash_moves_when_a_changed_attribute_name_is_added || bad hash_moves_when_a_changed_attribute_name_is_added
jq '(.resource_changes[] | select(.address=="google_cloud_run_v2_service.api") | .change) |= (.before = {image:"old",name:"api",labels:"a"} | .after = {image:"new",name:"api",labels:"b"})' "$tmp/plan.json" >"$tmp/names2.json"
[ "$(bash "$tool" hash "$tmp/names2.json")" != "$h0" ] && ok hash_moves_when_the_changed_names_differ_not_just_their_count || bad hash_moves_when_the_changed_names_differ_not_just_their_count
cp "$tmp/plan.json" "$tmp/identical.json"
[ "$(bash "$tool" hash "$tmp/identical.json")" = "$h0" ] && ok identical_plans_hash_identically || bad identical_plans_hash_identically
# An attribute that is the same before and after is not a changed name.
jq '(.resource_changes[] | select(.address=="google_cloud_run_v2_service.api") | .change) |= (.before.same = "x" | .after.same = "x")' "$tmp/plan.json" >"$tmp/unchanged_attr.json"
[ "$(bash "$tool" hash "$tmp/unchanged_attr.json")" = "$h0" ] && ok an_unchanged_attribute_is_not_a_changed_name || bad an_unchanged_attribute_is_not_a_changed_name
# The hash covers the FULL name list even where the comment cuts it at 20.
jq '(.resource_changes[] | select(.address=="google_secret_manager_secret.new") | .change.after) += ([range(0;30)|{key:("k"+tostring),value:1}]|from_entries)' "$tmp/plan.json" >"$tmp/wide2.json"
jq '(.resource_changes[] | select(.address=="google_secret_manager_secret.new") | .change.after) += ([range(0;31)|{key:("k"+tostring),value:1}]|from_entries)' "$tmp/plan.json" >"$tmp/wide3.json"
[ "$(bash "$tool" hash "$tmp/wide2.json")" != "$(bash "$tool" hash "$tmp/wide3.json")" ] && ok hash_covers_names_beyond_the_comments_cut || bad hash_covers_names_beyond_the_comments_cut
jq '(.resource_changes[] | select(.address=="google_pubsub_topic.gone") | .address) = "google_pubsub_topic.other"' "$tmp/plan.json" >"$tmp/addr.json"
[ "$(bash "$tool" hash "$tmp/addr.json")" != "$h0" ] && ok hash_moves_on_address || bad hash_moves_on_address
jq '(.resource_changes[] | select(.address=="google_cloud_run_v2_service.api") | .change.actions) = ["delete","create"]' "$tmp/plan.json" >"$tmp/act.json"
[ "$(bash "$tool" hash "$tmp/act.json")" != "$h0" ] && ok hash_moves_on_action || bad hash_moves_on_action
jq '.resource_changes += [{"address":"google_x.extra","change":{"actions":["create"],"before":null,"after":{},"after_unknown":{}}}]' "$tmp/plan.json" >"$tmp/extra.json"
[ "$(bash "$tool" hash "$tmp/extra.json")" != "$h0" ] && ok hash_moves_on_an_added_change || bad hash_moves_on_an_added_change
jq '.resource_changes += [{"address":"google_x.noop","change":{"actions":["no-op"],"before":{},"after":{},"after_unknown":{}}}]' "$tmp/plan.json" >"$tmp/noop.json"
[ "$(bash "$tool" hash "$tmp/noop.json")" = "$h0" ] && ok hash_ignores_added_no_op || bad hash_ignores_added_no_op

# No changes: says so, and is NOT an error.
echo '{"resource_changes":[]}' >"$tmp/empty.json"
e=$(bash "$tool" comment "$tmp/empty.json" "$HEAD"); rc=$?
[ "$rc" = 0 ] && printf '%s' "$e" | grep -q 'No resource changes' && ok empty_plan_says_no_changes || bad "empty plan: rc=$rc $e"

# A name list beyond 20 is cut, still names only.
jq -n '{resource_changes:[{address:"a.b",change:{actions:["create"],before:null,after:([range(0;25)|{key:("k"+tostring),value:1}]|from_entries),after_unknown:{}}}]}' >"$tmp/wide.json"
w=$(bash "$tool" comment "$tmp/wide.json" "$HEAD")
printf '%s' "$w" | grep -q '+5 more' && ok long_name_list_is_cut || bad "no cut: $w"

# Fail closed: not a plan, not JSON, a missing file, a bad sha, a bad mode.
echo '{"format_version":"1.2"}' >"$tmp/notplan.json"
bash "$tool" comment "$tmp/notplan.json" "$HEAD" >/dev/null 2>&1; [ $? = 2 ] && ok not_a_plan_is_an_error || bad not_a_plan_is_an_error
echo 'not json' >"$tmp/junk.json"
bash "$tool" hash "$tmp/junk.json" >/dev/null 2>&1; [ $? = 2 ] && ok junk_is_an_error || bad junk_is_an_error
bash "$tool" hash "$tmp/missing.json" >/dev/null 2>&1; [ $? = 2 ] && ok missing_is_an_error || bad missing_is_an_error
bash "$tool" record "$tmp/plan.json" abc >/dev/null 2>&1; [ $? = 2 ] && ok short_sha_is_an_error || bad short_sha_is_an_error
bash "$tool" nope "$tmp/plan.json" "$HEAD" >/dev/null 2>&1; [ $? = 2 ] && ok bad_mode_is_an_error || bad bad_mode_is_an_error

if [ "$failures" -ne 0 ]; then echo "$failures failure(s)"; exit 1; fi
echo "all plan-summary cases passed"
