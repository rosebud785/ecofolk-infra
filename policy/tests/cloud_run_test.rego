package main

run(min, max) := {"name": "api", "template": [{"scaling": [{"min_instance_count": min, "max_instance_count": max}]}]}

test_cloud_run_dev_pass if {
	count(deny) == 0 with input as tf("environments/dev/run.tf", "google_cloud_run_v2_service", run(0, 3))
}

test_cloud_run_prod_pass if {
	count(deny) == 0 with input as tf("environments/prod/run.tf", "google_cloud_run_v2_service", run(0, 5))
}

test_cloud_run_min_fail if {
	msgs := deny with input as tf("environments/dev/run.tf", "google_cloud_run_v2_service", run(1, 3))
	denied_with(msgs, "min_instance_count must be the literal 0")
}

test_cloud_run_dev_max_fail if {
	msgs := deny with input as tf("environments/dev/run.tf", "google_cloud_run_v2_service", run(0, 4))
	denied_with(msgs, "max_instance_count 4 exceeds 3")
}

test_cloud_run_prod_max_fail if {
	msgs := deny with input as tf("environments/prod/run.tf", "google_cloud_run_v2_service", run(0, 6))
	denied_with(msgs, "max_instance_count 6 exceeds 5")
}

# modules/ may be called by dev, so it gets the dev ceiling.
test_cloud_run_module_uses_dev_max_fail if {
	msgs := deny with input as tf("modules/svc/run.tf", "google_cloud_run_v2_service", run(0, 5))
	denied_with(msgs, "max_instance_count 5 exceeds 3")
}

test_cloud_run_max_unset_fail if {
	msgs := deny with input as tf("environments/dev/run.tf", "google_cloud_run_v2_service", {"name": "api", "template": [{}]})
	denied_with(msgs, "max_instance_count must be set")
}

test_cloud_run_max_variable_fail if {
	msgs := deny with input as tf("environments/dev/run.tf", "google_cloud_run_v2_service", run(0, "${var.max}"))
	denied_with(msgs, "max_instance_count must be a literal number")
}
