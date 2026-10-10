package main

bucket(pap, ubla) := {"name": "b", "location": "northamerica-northeast1", "public_access_prevention": pap, "uniform_bucket_level_access": ubla}

test_bucket_pass if {
	count(deny) == 0 with input as tf("modules/storage/main.tf", "google_storage_bucket", bucket("enforced", true))
}

test_bucket_public_access_fail if {
	msgs := deny with input as tf("modules/storage/main.tf", "google_storage_bucket", bucket("inherited", true))
	denied_with(msgs, "public_access_prevention must be \"enforced\"")
}

test_bucket_uniform_access_fail if {
	msgs := deny with input as tf("modules/storage/main.tf", "google_storage_bucket", bucket("enforced", false))
	denied_with(msgs, "uniform_bucket_level_access must be true")
}

test_bucket_unset_fail if {
	msgs := deny with input as tf("modules/storage/main.tf", "google_storage_bucket", {"name": "b"})
	denied_with(msgs, "public_access_prevention")
	denied_with(msgs, "uniform_bucket_level_access")
}
