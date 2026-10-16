package main

container := {"secret_id": "SWEEP_TOKEN", "replication": [{"user_managed": [{"replicas": [{"location": "northamerica-northeast1"}]}]}]}

# The rule refuses the resource type itself, so the fixture carries no value at all.
version := {"secret": "${google_secret_manager_secret.s.id}"}

accessor := {"secret_id": "SWEEP_TOKEN", "role": "roles/secretmanager.secretAccessor", "member": "user:someone@example.com"}

test_secret_container_pass if {
	count(deny) == 0 with input as tf("modules/secrets/main.tf", "google_secret_manager_secret", container)
}

# Known-wrong: a version (a value) next to the containers.
test_secret_version_fail if {
	msgs := deny with input as tf("modules/secrets/main.tf", "google_secret_manager_secret_version", version)
	denied_with(msgs, "google_secret_manager_secret_version.fixture: Secret Manager versions (values) and secret IAM belong under a local-only/ path")
}

test_secret_version_env_fail if {
	msgs := deny with input as tf("environments/dev/main.tf", "google_secret_manager_secret_version", version)
	denied_with(msgs, "Secret Manager versions (values) and secret IAM belong under a local-only/ path")
}

# A directory merely named like it is not the exemption.
test_secret_version_lookalike_path_fail if {
	msgs := deny with input as tf("environments/dev/not-local-only/main.tf", "google_secret_manager_secret_version", version)
	denied_with(msgs, "Secret Manager versions (values) and secret IAM belong under a local-only/ path")
}

test_secret_version_local_only_pass if {
	count(deny) == 0 with input as tf("environments/dev/local-only/secrets.tf", "google_secret_manager_secret_version", version)
}

# Known-wrong: an accessor binding outside local-only/.
test_secret_iam_member_fail if {
	msgs := deny with input as tf("modules/secrets/main.tf", "google_secret_manager_secret_iam_member", accessor)
	denied_with(msgs, "google_secret_manager_secret_iam_member.fixture: Secret Manager versions (values) and secret IAM belong under a local-only/ path")
}

test_secret_iam_binding_fail if {
	msgs := deny with input as tf("environments/dev/iam.tf", "google_secret_manager_secret_iam_binding", object.union(accessor, {"members": []}))
	denied_with(msgs, "Secret Manager versions (values) and secret IAM belong under a local-only/ path")
}

test_secret_iam_local_only_pass if {
	count(deny) == 0 with input as tf("environments/dev/local-only/iam.tf", "google_secret_manager_secret_iam_member", accessor)
}
