package main

sql(tier, availability, protection) := {
	"deletion_protection": protection,
	"settings": [{"tier": tier, "availability_type": availability}],
}

test_sql_dev_pass if {
	count(deny) == 0 with input as tf("environments/dev/db.tf", "google_sql_database_instance", sql("db-f1-micro", "ZONAL", false))
}

test_sql_prod_pass if {
	count(deny) == 0 with input as tf("environments/prod/db.tf", "google_sql_database_instance", sql("db-custom-1-3840", "REGIONAL", true))
}

test_sql_tier_fail if {
	msgs := deny with input as tf("environments/dev/db.tf", "google_sql_database_instance", sql("db-custom-8-32768", "ZONAL", false))
	denied_with(msgs, "tier db-custom-8-32768 is not on the allowlist")
}

test_sql_tier_variable_fail if {
	msgs := deny with input as tf("environments/dev/db.tf", "google_sql_database_instance", sql("${var.tier}", "ZONAL", false))
	denied_with(msgs, "is not on the allowlist")
}

test_sql_dev_regional_fail if {
	msgs := deny with input as tf("environments/dev/db.tf", "google_sql_database_instance", sql("db-f1-micro", "REGIONAL", false))
	denied_with(msgs, "availability_type must not be REGIONAL outside prod")
}

test_sql_prod_deletion_protection_fail if {
	msgs := deny with input as tf("environments/prod/db.tf", "google_sql_database_instance", sql("db-f1-micro", "ZONAL", false))
	denied_with(msgs, "deletion_protection = true")
}

test_sql_prod_deletion_protection_unset_fail if {
	msgs := deny with input as tf("environments/prod/db.tf", "google_sql_database_instance", {"settings": [{"tier": "db-f1-micro"}]})
	denied_with(msgs, "deletion_protection = true")
}

# --- deletion_protection judged at the module call site (#89) ---------------------------------------------

sql_mod := res_file("modules/db/main.tf", "google_sql_database_instance", {
	"deletion_protection": "${var.deletion_protection}",
	"settings": [{"tier": "db-f1-micro", "availability_type": "ZONAL"}],
})

prot_var(d) := var_file("modules/db/variables.tf", "deletion_protection", {"type": "bool", "default": d})

prod_call(body) := call_file("environments/prod/main.tf", "db", object.union({"source": "../../modules/db"}, body))

test_sql_prod_call_site_false_fails if {
	msgs := deny with input as [sql_mod, prot_var(true), prod_call({"deletion_protection": false})]
	denied_with(msgs, "passes deletion_protection = false")
	denied_with(msgs, "prod instances need deletion_protection = true")
}

test_sql_prod_call_site_true_passes if {
	count(deny) == 0 with input as [sql_mod, prot_var(true), prod_call({"deletion_protection": true})]
}

test_sql_prod_call_site_omitted_with_true_default_passes if {
	count(deny) == 0 with input as [sql_mod, prot_var(true), prod_call({})]
}

test_sql_prod_call_site_omitted_with_false_default_fails if {
	msgs := deny with input as [sql_mod, prot_var(false), prod_call({})]
	denied_with(msgs, "omits deletion_protection")
}

test_sql_prod_call_site_nonliteral_fails if {
	msgs := deny with input as [sql_mod, prot_var(true), prod_call({"deletion_protection": "${local.protect}"})]
	denied_with(msgs, "passes deletion_protection")
}

test_sql_dev_call_site_false_passes if {
	call := call_file("environments/dev/main.tf", "db", {"source": "../../modules/db", "deletion_protection": false})
	count(deny) == 0 with input as [sql_mod, prot_var(true), call]
}

test_sql_module_var_without_default_fails if {
	nodefault := var_file("modules/db/variables.tf", "deletion_protection", {"type": "bool"})
	msgs := deny with input as [sql_mod, nodefault, prod_call({"deletion_protection": true})]
	denied_with(msgs, "needs a literal default")
}
