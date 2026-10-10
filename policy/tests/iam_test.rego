package main

member := {"project": "ecofolk-dev", "role": "roles/viewer", "member": "user:someone@example.com"}

test_sa_key_pass if {
	count(deny) == 0 with input as tf("environments/dev/sa.tf", "google_service_account", {"account_id": "worker"})
}

test_sa_key_fail if {
	msgs := deny with input as tf("environments/dev/sa.tf", "google_service_account_key", {"service_account_id": "worker"})
	denied_with(msgs, "google_service_account_key is forbidden everywhere")
}

# "Anywhere" includes local-only/.
test_sa_key_local_only_fail if {
	msgs := deny with input as tf("environments/dev/local-only/sa.tf", "google_service_account_key", {"service_account_id": "worker"})
	denied_with(msgs, "google_service_account_key is forbidden everywhere")
}

test_iam_local_only_pass if {
	count(deny) == 0 with input as tf("environments/dev/local-only/iam.tf", "google_project_iam_member", member)
}

test_iam_outside_local_only_fail if {
	msgs := deny with input as tf("environments/dev/iam.tf", "google_project_iam_member", member)
	denied_with(msgs, "IAM resources belong under a local-only/ path")
}

test_wif_pool_outside_local_only_fail if {
	msgs := deny with input as tf("modules/project/wif.tf", "google_iam_workload_identity_pool", {"workload_identity_pool_id": "gh"})
	denied_with(msgs, "IAM resources belong under a local-only/ path")
}

# A directory merely named like it is not the exemption.
test_iam_lookalike_path_fail if {
	msgs := deny with input as tf("environments/dev/not-local-only/iam.tf", "google_project_iam_member", member)
	denied_with(msgs, "IAM resources belong under a local-only/ path")
}

# R1: the top-level local-only/ (CODEOWNERS) is scanned too, and "anywhere" holds there.
test_sa_key_toplevel_local_only_fail if {
	msgs := deny with input as tf("local-only/sa.tf", "google_service_account_key", {"service_account_id": "worker"})
	denied_with(msgs, "google_service_account_key is forbidden everywhere")
}

test_iam_toplevel_dir_fail if {
	msgs := deny with input as tf("foo/iam.tf", "google_project_iam_member", member)
	denied_with(msgs, "IAM resources belong under a local-only/ path")
}
