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
