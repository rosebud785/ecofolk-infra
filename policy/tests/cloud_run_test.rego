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

# R3: only v2 services and v2 jobs; the other Cloud Run shapes escape the cap.
test_cloud_run_v2_job_pass if {
	count(deny) == 0 with input as tf("environments/dev/job.tf", "google_cloud_run_v2_job", {"name": "migrate", "location": "northamerica-northeast1"})
}

test_cloud_run_v1_service_fail if {
	msgs := deny with input as tf("environments/dev/run.tf", "google_cloud_run_service", {"name": "api", "template": [{"metadata": [{"annotations": {"autoscaling.knative.dev/maxScale": "100"}}]}]})
	denied_with(msgs, "only google_cloud_run_v2_service and google_cloud_run_v2_job are allowed")
}

test_cloud_run_worker_pool_fail if {
	msgs := deny with input as tf("environments/dev/pool.tf", "google_cloud_run_v2_worker_pool", {"name": "w"})
	denied_with(msgs, "only google_cloud_run_v2_service and google_cloud_run_v2_job are allowed")
}

test_cloud_run_domain_mapping_fail if {
	msgs := deny with input as tf("environments/dev/dm.tf", "google_cloud_run_domain_mapping", {"name": "api.example.com"})
	denied_with(msgs, "only google_cloud_run_v2_service and google_cloud_run_v2_job are allowed")
}

# Cloud Run IAM types are the IAM rule's: allowed under local-only/ ...
test_cloud_run_iam_local_only_pass if {
	count(deny) == 0 with input as tf("local-only/run_iam.tf", "google_cloud_run_v2_service_iam_member", {"name": "api", "role": "roles/run.invoker", "member": "allUsers"})
}

# ... and refused elsewhere by the IAM rule only, not by the Cloud Run type rule.
test_cloud_run_iam_outside_local_only_fail if {
	msgs := deny with input as tf("environments/dev/run_iam.tf", "google_cloud_run_service_iam_member", {"service": "api", "role": "roles/run.invoker", "member": "allUsers"})
	denied_with(msgs, "IAM resources belong under a local-only/ path")
	not denied_with(msgs, "only google_cloud_run_v2_service")
}

run_with_service_scaling(s) := object.union(run(0, 3), {"scaling": [s]})

test_cloud_run_scaling_mode_automatic_pass if {
	count(deny) == 0 with input as tf("environments/dev/run.tf", "google_cloud_run_v2_service", run_with_service_scaling({"scaling_mode": "AUTOMATIC"}))
}

test_cloud_run_scaling_mode_manual_fail if {
	msgs := deny with input as tf("environments/dev/run.tf", "google_cloud_run_v2_service", run_with_service_scaling({"scaling_mode": "MANUAL", "manual_instance_count": 2}))
	denied_with(msgs, "scaling_mode must be the literal \"AUTOMATIC\", got MANUAL")
	denied_with(msgs, "manual_instance_count is forbidden")
}

test_cloud_run_manual_instance_count_fail if {
	msgs := deny with input as tf("environments/dev/run.tf", "google_cloud_run_v2_service", run_with_service_scaling({"manual_instance_count": 1}))
	denied_with(msgs, "manual_instance_count is forbidden")
}

test_cloud_run_scaling_mode_variable_fail if {
	msgs := deny with input as tf("environments/prod/run.tf", "google_cloud_run_v2_service", run_with_service_scaling({"scaling_mode": "${var.mode}"}))
	denied_with(msgs, "scaling_mode must be the literal \"AUTOMATIC\"")
}

test_cloud_run_scaling_mode_lowercase_fail if {
	msgs := deny with input as tf("environments/dev/run.tf", "google_cloud_run_v2_service", run_with_service_scaling({"scaling_mode": "automatic"}))
	denied_with(msgs, "scaling_mode must be the literal \"AUTOMATIC\"")
}

# R1: a local module outside environments/ and modules/ is scanned, and gets the dev ceiling.
test_cloud_run_toplevel_module_dir_fail if {
	msgs := deny with input as tf("foo/main.tf", "google_cloud_run_v2_service", run(0, 5))
	denied_with(msgs, "max_instance_count 5 exceeds 3")
}
