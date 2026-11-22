# plan-summary.jq — the NAMES-ONLY comment body for plan-summary.sh (ecofolk-infra#162). Called with
#   jq -r --arg head <40-hex> --arg rec "<plan-record line>" -f plan-summary.jq <terraform show -json plan>
# No value of any attribute is ever selected: only addresses, actions and attribute NAMES.

def clean: gsub("[\n\r`]"; "");

# Changed entries: everything except pure no-op and read-only data reads.
def changed: [.resource_changes[] | select((.change.actions) as $a | ($a != ["no-op"] and $a != ["read"]))];

def obj: if type == "object" then . else {} end;

# Attribute names that differ between before and after, or are unknown until apply.
def names:
  (.change.before | obj) as $b
  | (.change.after | obj) as $a
  | (.change.after_unknown | obj) as $u
  | ([($b | keys[]), ($a | keys[]), ($u | keys[])] | unique)
  | map(select(. as $k | ($b[$k] != $a[$k]) or ($u[$k] == true)))
  | map(clean);

def kind:
  (.change.actions) as $x
  | if ($x | index("delete")) and ($x | index("create")) then "replace"
    elif $x == ["create"] then "add"
    elif $x == ["update"] then "change"
    elif $x == ["delete"] then "destroy"
    else "other" end;

def rank: if kind == "replace" then 0 elif kind == "destroy" then 1 else 2 end;

def item:
  (names) as $n
  | "- `" + (.address | clean) + "` " + kind
    + (if ($n | length) == 0 then ""
       else " (" + ($n[0:20] | join(", ")) + (if ($n | length) > 20 then ", +" + (($n | length) - 20 | tostring) + " more" else "" end) + ")"
       end);

changed as $c
| ($c | map(kind)) as $k
| ($k | map(select(. == "add")) | length) as $add
| ($k | map(select(. == "change")) | length) as $chg
| ($k | map(select(. == "destroy")) | length) as $del
| ($k | map(select(. == "replace")) | length) as $rep
| "### terraform plan (dev) for `" + ($head[0:12]) + "`: names only, no values\n\n"
  + (if ($del + $rep) > 0 then "**DESTROY / REPLACE: " + ($del | tostring) + " destroy, " + ($rep | tostring) + " replace.**\n\n" else "" end)
  + "Plan: " + ($add | tostring) + " to add, " + ($chg | tostring) + " to change, " + ($del | tostring) + " to destroy, " + ($rep | tostring) + " to replace.\n\n"
  + (if ($c | length) == 0 then "No resource changes.\n\n"
     else (($c | sort_by([rank, .address]) | map(item) | join("\n")) + "\n\n") end)
  + "Changed attributes are named, never shown. Drift rule: the apply on merge re-plans and REFUSES unless this record matches its own plan and the merged tree equals this head's tree.\n\n"
  + $rec
