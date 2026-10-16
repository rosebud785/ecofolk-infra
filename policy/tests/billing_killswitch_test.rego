package main

ks_var_file(default_value) := var_file("modules/billing_killswitch/variables.tf", "project_allowlist", {"type": "${list(string)}", "default": default_value})

ks_call(allowlist) := call_file("environments/dev/main.tf", "billing_killswitch", {"source": "../../modules/billing_killswitch", "project_allowlist": allowlist})

test_killswitch_default_dev_pass if {
	count(deny) == 0 with input as [ks_var_file(["ecofolk-dev"])]
}

# Known-wrong: prod on the module's default allowlist.
test_killswitch_default_prod_fail if {
	msgs := deny with input as [ks_var_file(["ecofolk-dev", "ecofolk-prod"])]
	denied_with(msgs, "variable.project_allowlist default holds ecofolk-prod: the billing kill-switch allowlist must never contain a *-prod project")
}

test_killswitch_default_prod_upper_case_fail if {
	msgs := deny with input as [ks_var_file(["ECOFOLK-PROD"])]
	denied_with(msgs, "must never contain a *-prod project")
}

# A variable with no default is judged at its call sites (below), not refused here.
test_killswitch_variable_without_default_pass if {
	count(deny) == 0 with input as [var_file("modules/billing_killswitch/variables.tf", "project_allowlist", {"type": "${list(string)}"})]
}

test_killswitch_call_dev_pass if {
	count(deny) == 0 with input as [ks_var_file(["ecofolk-dev"]), ks_call(["ecofolk-dev"])]
}

# Known-wrong: a call site passing a prod id.
test_killswitch_call_prod_fail if {
	msgs := deny with input as [ks_var_file(["ecofolk-dev"]), ks_call(["ecofolk-prod"])]
	denied_with(msgs, "environments/dev/main.tf: module.billing_killswitch project_allowlist holds ecofolk-prod")
}

# Not a literal list: can't be checked, so refused.
test_killswitch_call_var_fail if {
	msgs := deny with input as [ks_var_file(["ecofolk-dev"]), ks_call("${var.allowlist}")]
	denied_with(msgs, "module.billing_killswitch project_allowlist must be a literal list of project ids")
}

# An interpolated entry inside a literal list is refused too.
test_killswitch_call_interpolated_entry_fail if {
	msgs := deny with input as [ks_var_file(["ecofolk-dev"]), ks_call(["ecofolk-dev", "${var.project_id}"])]
	denied_with(msgs, "must be a literal project id")
}

test_killswitch_default_var_fail if {
	msgs := deny with input as [ks_var_file("${local.ids}")]
	denied_with(msgs, "variable.project_allowlist default must be a literal list of project ids")
}
