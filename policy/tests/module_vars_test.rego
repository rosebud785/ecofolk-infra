# ecofolk-infra#39 (C7b): a module's var.X judged by its default and every call site.
package main

sql_var := {"deletion_protection": true, "settings": [{"tier": "${var.tier}", "availability_type": "ZONAL"}]}

sql_module(default_body) := [
	res_file("modules/db/main.tf", "google_sql_database_instance", sql_var),
	var_file("modules/db/variables.tf", "tier", default_body),
]

run_var := {"name": "api", "template": [{"scaling": [{"min_instance_count": 0, "max_instance_count": "${var.max}"}]}]}

run_module := [
	res_file("modules/svc/main.tf", "google_cloud_run_v2_service", run_var),
	var_file("modules/svc/variables.tf", "max", {"default": 3}),
]

# --- the module's default ---

test_module_var_default_on_allowlist_pass if {
	count(deny) == 0 with input as sql_module({"default": "db-f1-micro"})
}

test_module_var_default_not_on_allowlist_fail if {
	msgs := deny with input as sql_module({"default": "db-custom-8-32768"})
	denied_with(msgs, "tier = var.tier, whose default db-custom-8-32768 fails the tier allowlist")
}

# The default is judged under the dev cap, even though a prod call could pass 5.
test_module_var_default_over_dev_cap_fail if {
	msgs := deny with input as [
		res_file("modules/svc/main.tf", "google_cloud_run_v2_service", run_var),
		var_file("modules/svc/variables.tf", "max", {"default": 5}),
	]
	denied_with(msgs, "max_instance_count = var.max, whose default 5 fails the cap of 3 instances")
}

test_module_var_no_default_fail if {
	msgs := deny with input as sql_module({"type": "${string}"})
	denied_with(msgs, "tier = var.tier needs a literal default in modules/db")
}

test_module_var_undeclared_fail if {
	msgs := deny with input as [res_file("modules/db/main.tf", "google_sql_database_instance", sql_var)]
	denied_with(msgs, "but modules/db declares no variable \"tier\"")
}

# --- call sites: prod vs dev limits ---

test_module_var_prod_call_passes_5_pass if {
	count(deny) == 0 with input as array.concat(run_module, [call_file("environments/prod/main.tf", "svc", {"source": "../../modules/svc", "max": 5})])
}

test_module_var_dev_call_passes_5_fail if {
	msgs := deny with input as array.concat(run_module, [call_file("environments/dev/main.tf", "svc", {"source": "../../modules/svc", "max": 5})])
	denied_with(msgs, "environments/dev/main.tf: module.svc passes max = 5 to modules/svc (max_instance_count), which fails the cap of 3 instances")
}

test_module_var_prod_call_passes_6_fail if {
	msgs := deny with input as array.concat(run_module, [call_file("environments/prod/main.tf", "svc", {"source": "../../modules/svc", "max": 6})])
	denied_with(msgs, "module.svc passes max = 6 to modules/svc (max_instance_count), which fails the cap of 5 instances")
}

# Every call site counts: one good call doesn't excuse another.
test_module_var_every_call_site_fail if {
	msgs := deny with input as array.concat(run_module, [
		call_file("environments/prod/main.tf", "svc", {"source": "../../modules/svc", "max": 5}),
		call_file("environments/dev/main.tf", "svc", {"source": "../../modules/svc", "max": 5}),
	])
	denied_with(msgs, "environments/dev/main.tf: module.svc passes max = 5")
	not denied_with(msgs, "environments/prod/main.tf")
}

# --- omitted argument ---

test_module_var_omitted_arg_uses_default_pass if {
	count(deny) == 0 with input as array.concat(sql_module({"default": "db-f1-micro"}), [call_file("environments/dev/main.tf", "db", {"source": "../../modules/db"})])
}

# Omitted with no default to fall back on: refused (Terraform would also refuse the call).
test_module_var_omitted_arg_no_default_fail if {
	msgs := deny with input as array.concat(sql_module({"type": "${string}"}), [call_file("environments/dev/main.tf", "db", {"source": "../../modules/db"})])
	denied_with(msgs, "tier = var.tier needs a literal default")
}

# --- non-literal at the call site ---

test_module_var_literal_at_call_site_pass if {
	count(deny) == 0 with input as array.concat(sql_module({"default": "db-f1-micro"}), [call_file("environments/dev/main.tf", "db", {"source": "../../modules/db", "tier": "db-g1-small"})])
}

test_module_var_literal_off_allowlist_at_call_site_fail if {
	msgs := deny with input as array.concat(sql_module({"default": "db-f1-micro"}), [call_file("environments/prod/main.tf", "db", {"source": "../../modules/db", "tier": "db-custom-8-32768"})])
	denied_with(msgs, "module.db passes tier = db-custom-8-32768 to modules/db (tier), which fails the tier allowlist")
}

test_module_var_variable_at_call_site_fail if {
	msgs := deny with input as array.concat(sql_module({"default": "db-f1-micro"}), [call_file("environments/dev/main.tf", "db", {"source": "../../modules/db", "tier": "${var.tier}"})])
	denied_with(msgs, "module.db passes tier = ${var.tier}")
}

test_module_var_local_at_call_site_fail if {
	msgs := deny with input as array.concat(run_module, [call_file("environments/prod/main.tf", "svc", {"source": "../../modules/svc", "max": "${local.max}"})])
	denied_with(msgs, "module.svc passes max = ${local.max}")
}

test_module_var_conditional_at_call_site_fail if {
	msgs := deny with input as array.concat(run_module, [call_file("environments/prod/main.tf", "svc", {"source": "../../modules/svc", "max": "${var.big ? 5 : 3}"})])
	denied_with(msgs, "module.svc passes max = ${var.big ? 5 : 3}")
}

# --- source resolution ---

# "./" segments and a trailing slash normalise away; a module calling a sibling module resolves too.
test_module_var_source_normalised_pass if {
	count(deny) == 0 with input as array.concat(run_module, [
		call_file("environments/prod/main.tf", "svc", {"source": "./../../modules/./svc/", "max": 5}),
		call_file("modules/app/main.tf", "svc", {"source": "../svc", "max": 2}),
	])
}

# A normalised source still catches a bad value: the dev call can't hide behind an odd spelling.
test_module_var_source_normalised_still_judged_fail if {
	msgs := deny with input as array.concat(run_module, [call_file("environments/dev/main.tf", "svc", {"source": "../prod/../../modules/svc", "max": 5})])
	denied_with(msgs, "module.svc passes max = 5 to modules/svc")
}

test_module_var_unresolvable_source_fail if {
	msgs := deny with input as array.concat(run_module, [call_file("environments/dev/main.tf", "svc", {"source": "../../modules/svcc", "max": 5})])
	denied_with(msgs, "module.svc: source ../../modules/svcc doesn't resolve to a directory with tracked *.tf")
}

test_module_var_source_above_repo_root_fail if {
	msgs := deny with input as array.concat(run_module, [call_file("environments/dev/main.tf", "svc", {"source": "../../../modules/svc", "max": 5})])
	denied_with(msgs, "module.svc: source ../../../modules/svc doesn't resolve")
}

# --- other expressions are refused as before ---

test_module_local_tier_fail if {
	msgs := deny with input as [res_file("modules/db/main.tf", "google_sql_database_instance", {"deletion_protection": true, "settings": [{"tier": "${local.tier}"}]})]
	denied_with(msgs, "tier ${local.tier} is not on the allowlist")
}

test_module_var_interpolated_tier_fail if {
	msgs := deny with input as [
		res_file("modules/db/main.tf", "google_sql_database_instance", {"deletion_protection": true, "settings": [{"tier": "${var.tier}-micro"}]}),
		var_file("modules/db/variables.tf", "tier", {"default": "db-f1"}),
	]
	denied_with(msgs, "tier ${var.tier}-micro is not on the allowlist")
}

test_module_var_conditional_max_fail if {
	msgs := deny with input as [res_file("modules/svc/main.tf", "google_cloud_run_v2_service", {"name": "api", "template": [{"scaling": [{"min_instance_count": 0, "max_instance_count": "${var.big ? 5 : 3}"}]}]})]
	denied_with(msgs, "max_instance_count must be a literal number")
}

# Only a file directly under modules/<m>/ gets the exception; a nested directory or a root module doesn't.
test_module_var_nested_dir_fail if {
	msgs := deny with input as [
		res_file("modules/db/inner/main.tf", "google_sql_database_instance", sql_var),
		var_file("modules/db/inner/variables.tf", "tier", {"default": "db-f1-micro"}),
	]
	denied_with(msgs, "tier ${var.tier} is not on the allowlist")
}

test_module_var_in_environment_fail if {
	msgs := deny with input as [
		res_file("environments/dev/db.tf", "google_sql_database_instance", sql_var),
		var_file("environments/dev/variables.tf", "tier", {"default": "db-f1-micro"}),
	]
	denied_with(msgs, "tier ${var.tier} is not on the allowlist")
}
