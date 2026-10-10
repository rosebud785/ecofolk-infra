# Buckets: no public access, uniform (bucket-level) access only.
package main

buckets contains r if {
	some r in resources
	r.type == "google_storage_bucket"
}

deny contains msg if {
	some r in buckets
	object.get(r.body, "public_access_prevention", "<unset>") != "enforced"
	msg := sprintf("%s: public_access_prevention must be \"enforced\"", [label(r)])
}

deny contains msg if {
	some r in buckets
	object.get(r.body, "uniform_bucket_level_access", "<unset>") != true
	msg := sprintf("%s: uniform_bucket_level_access must be true", [label(r)])
}
