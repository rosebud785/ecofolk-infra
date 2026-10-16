# Billing kill-switch allowlist (ecofolk-infra#15, C7). modules/billing_killswitch unlinks billing from any
# project on `project_allowlist`; unlinking prod's billing takes the beta down, so the allowlist must never
# hold a *-prod project id.
#
# Checked wherever the name appears: every `variable "project_allowlist"` default, and every module block
# that passes `project_allowlist`. Each must be a literal list of literal strings ("${...}" can't be checked
# without a plan, so it is refused), and no entry may end in "-prod" (case-insensitive).
package main

allowlist_values contains {"where": sprintf("%s: variable.project_allowlist default", [f.path]), "value": b["default"]} if {
	some f in input
	some b in object.get(object.get(f.contents, "variable", {}), "project_allowlist", [])
	"default" in object.keys(b)
}

allowlist_values contains {"where": sprintf("%s: module.%s project_allowlist", [m.path, m.name]), "value": m.body.project_allowlist} if {
	some m in modules
	"project_allowlist" in object.keys(m.body)
}

deny contains msg if {
	some a in allowlist_values
	not is_array(a.value)
	msg := sprintf("%s must be a literal list of project ids, got %v", [a.where, a.value])
}

deny contains msg if {
	some a in allowlist_values
	is_array(a.value)
	some v in a.value
	not literal_id(v)
	msg := sprintf("%s: entry %v must be a literal project id", [a.where, v])
}

deny contains msg if {
	some a in allowlist_values
	is_array(a.value)
	some v in a.value
	is_string(v)
	endswith(lower(v), "-prod")
	msg := sprintf("%s holds %v: the billing kill-switch allowlist must never contain a *-prod project", [a.where, v])
}

literal_id(v) if {
	is_string(v)
	not contains(v, "${")
}
