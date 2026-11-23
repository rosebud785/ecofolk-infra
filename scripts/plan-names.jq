# plan-names.jq — shared jq definitions for plan-summary.sh (ecofolk-infra#162). Included by plan-summary.jq (the
# comment) and by the hash program in plan-summary.sh, so the names the reviewer READS are exactly the names the
# record HASHES. No value of any attribute is ever selected: only addresses, actions and attribute NAMES.

def clean: gsub("[\n\r`]"; "");

# Changed entries: everything except pure no-op and read-only data reads.
def changed: [.resource_changes[] | select((.change.actions) as $a | ($a != ["no-op"] and $a != ["read"]))];

def obj: if type == "object" then . else {} end;

# Attribute names that differ between before and after, or are unknown until apply. Sorted, unique, cleaned.
def names:
  (.change.before | obj) as $b
  | (.change.after | obj) as $a
  | (.change.after_unknown | obj) as $u
  | ([($b | keys[]), ($a | keys[]), ($u | keys[])] | unique)
  | map(select(. as $k | ($b[$k] != $a[$k]) or ($u[$k] == true)))
  | map(clean)
  | sort;

def kind:
  (.change.actions) as $x
  | if ($x | index("delete")) and ($x | index("create")) then "replace"
    elif $x == ["create"] then "add"
    elif $x == ["update"] then "change"
    elif $x == ["delete"] then "destroy"
    else "other" end;

# One line of the record's hash input: address | actions | every changed attribute NAME (the full list, not the cut one
# the comment shows). Two plans with the same resource and action but different changed attributes hash differently.
def hash_line: (.address | clean) + "|" + (.change.actions | join(",")) + "|" + (names | join(","));
