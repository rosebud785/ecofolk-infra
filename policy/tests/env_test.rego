package main

# C7 env rule (#13): a passing and a failing fixture for each part.

test_env_name_var_env_pass if {
	count(deny_env) == 0 with input as tf("modules/x/main.tf", "google_cloud_scheduler_job", {"name": "job-${var.env}"})
}

test_env_name_suffix_pass if {
	count(deny_env) == 0 with input as tf("modules/x/main.tf", "google_cloud_scheduler_job", {"name": "${var.name}${local.env_suffix}"})
}

test_env_name_suffix_in_function_pass if {
	count(deny_env) == 0 with input as tf("modules/x/main.tf", "google_sql_database", {"name": "ecofolk${replace(local.env_suffix, \"-\", \"_\")}"})
}

test_env_name_literal_fail if {
	msgs := deny_env with input as tf("modules/x/main.tf", "google_cloud_scheduler_job", {"name": "idle-sit-sweep"})
	denied_with(msgs, "name must carry env")
}

test_env_name_bare_var_fail if {
	msgs := deny_env with input as tf("environments/qa/main.tf", "google_cloud_scheduler_job", {"name": "${var.name}"})
	denied_with(msgs, "name must carry env")
}

# var.env_vars is not var.env.
test_env_name_lookalike_var_fail if {
	msgs := deny_env with input as tf("modules/x/main.tf", "google_cloud_scheduler_job", {"name": "${var.env_vars}"})
	denied_with(msgs, "name must carry env")
}

# Outside the interpolation, "var.env" is just text.
test_env_name_text_fail if {
	msgs := deny_env with input as tf("modules/x/main.tf", "google_cloud_scheduler_job", {"name": "var.env"})
	denied_with(msgs, "name must carry env")
}

test_env_secret_id_fail if {
	msgs := deny_env with input as tf("modules/x/main.tf", "google_secret_manager_secret", {"secret_id": "${each.value}", "labels": {"env": "${var.env}"}})
	denied_with(msgs, "secret_id must carry env")
}

test_env_site_id_fail if {
	msgs := deny_env with input as tf("modules/x/main.tf", "google_firebase_hosting_site", {"site_id": "${var.project_id}-web"})
	denied_with(msgs, "site_id must carry env")
}

test_env_repository_id_fail if {
	msgs := deny_env with input as tf("modules/x/main.tf", "google_artifact_registry_repository", {"repository_id": "${var.repository_id}", "labels": {"env": "${var.env}"}})
	denied_with(msgs, "repository_id must carry env")
}

# A resource with no name argument is not named.
test_env_unnamed_pass if {
	count(deny_env) == 0 with input as tf("modules/x/main.tf", "google_project_service", {"service": "run.googleapis.com"})
}

test_env_local_only_pass if {
	count(deny_env) == 0 with input as tf("environments/dev/local-only/x.tf", "google_storage_bucket", {"name": "b"})
}

test_env_label_pass if {
	count(deny_env) == 0 with input as tf("modules/x/main.tf", "google_storage_bucket", {"name": "b${local.env_suffix}", "labels": {"env": "${var.env}"}})
}

test_env_label_literal_pass if {
	count(deny_env) == 0 with input as tf("modules/x/main.tf", "google_pubsub_topic", {"name": "t${local.env_suffix}", "labels": {"env": "dev"}})
}

test_env_label_missing_fail if {
	msgs := deny_env with input as tf("modules/x/main.tf", "google_storage_bucket", {"name": "b${local.env_suffix}", "labels": {"component": "media"}})
	denied_with(msgs, "must carry an env label")
}

test_env_label_unset_fail if {
	msgs := deny_env with input as tf("modules/x/main.tf", "google_cloud_run_v2_service", {"name": "s${local.env_suffix}"})
	denied_with(msgs, "must carry an env label")
}

test_env_label_bad_value_fail if {
	msgs := deny_env with input as tf("modules/x/main.tf", "google_storage_bucket", {"name": "b${local.env_suffix}", "labels": {"env": "staging"}})
	denied_with(msgs, "must carry an env label")
}

test_env_sql_user_labels_pass if {
	count(deny_env) == 0 with input as tf("modules/x/main.tf", "google_sql_database_instance", {"name": "pg${local.env_suffix}", "settings": [{"user_labels": {"env": "${var.env}"}}]})
}

test_env_sql_user_labels_fail if {
	msgs := deny_env with input as tf("modules/x/main.tf", "google_sql_database_instance", {"name": "pg${local.env_suffix}", "settings": [{"tier": "db-f1-micro"}]})
	denied_with(msgs, "must carry an env label")
}

test_env_alert_policy_user_labels_fail if {
	msgs := deny_env with input as tf("modules/x/main.tf", "google_monitoring_alert_policy", {"display_name": "x"})
	denied_with(msgs, "must carry an env label")
}

test_env_alert_policy_user_labels_pass if {
	count(deny_env) == 0 with input as tf("modules/x/main.tf", "google_monitoring_alert_policy", {"display_name": "x", "user_labels": {"env": "${var.env}"}})
}

test_env_iam_sql_user_exempt_pass if {
	count(deny_env) == 0 with input as tf("modules/x/main.tf", "google_sql_user", {"name": "${trimsuffix(var.sa, \".gserviceaccount.com\")}", "type": "CLOUD_IAM_SERVICE_ACCOUNT"})
}

test_env_builtin_sql_user_still_checked_fail if {
	msgs := deny_env with input as tf("modules/x/main.tf", "google_sql_user", {"name": "app", "type": "BUILT_IN"})
	denied_with(msgs, "must carry env")
}
