# Cloud SQL: tier on the allowlist in data.json, no REGIONAL (HA) outside prod, and prod instances carry
# deletion_protection = true.
package main

sql_instances contains r if {
	some r in resources
	r.type == "google_sql_database_instance"
}

sql_settings(r) := object.get(r.body, "settings", [])

deny contains msg if {
	some r in sql_instances
	count(sql_settings(r)) == 0
	msg := sprintf("%s: settings.tier must be set", [label(r)])
}

deny contains msg if {
	some r in sql_instances
	some s in sql_settings(r)
	tier := object.get(s, "tier", "<unset>")
	not tier in data.ecofolk.sql_tier_allowlist
	msg := sprintf("%s: tier %v is not on the allowlist (policy/data.json): %v", [label(r), tier, data.ecofolk.sql_tier_allowlist])
}

deny contains msg if {
	some r in sql_instances
	not is_prod(r.path)
	some s in sql_settings(r)
	v := s.availability_type
	refused_availability(v)
	msg := sprintf("%s: availability_type must not be REGIONAL outside prod (and must be a literal), got %v", [label(r), v])
}

refused_availability(v) if v == "REGIONAL"

refused_availability(v) if not is_string(v)

refused_availability(v) if contains(v, "${")

deny contains msg if {
	some r in sql_instances
	is_prod(r.path)
	object.get(r.body, "deletion_protection", "<unset>") != true
	msg := sprintf("%s: prod instances need deletion_protection = true", [label(r)])
}
