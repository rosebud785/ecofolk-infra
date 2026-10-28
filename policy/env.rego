# C7 env rule (ecofolk-infra#13): every named resource carries env. The QA namespace lives inside
# ecofolk-dev with no project-level isolation, so names and labels are what keep a dev resource and a qa
# resource apart (with qa's separate state).
#
#   1. A named resource's name must reference the environment: var.env, or local.env_suffix (the per-module
#      suffix, "" for dev and prod, "-qa" for qa). A literal or a bare var.name is refused: the same
#      module called with env = "qa" would reuse dev's name in the same project.
#   2. A resource of a type that takes labels must carry an `env` label, set to var.env or a literal
#      dev, qa or prod.
#
# The name argument is `name`, except the types in name_args. local-only/ is exempt, as for IAM.
#
# Its own rule set, deny_env (conftest runs every deny_* rule), so the other rules' fixtures, which carry
# no env, still test only what they test.
#
# Surface path (CODEOWNERS): weakening this needs ARCHITECT APPROVED.
package main

name_args := {
	"google_secret_manager_secret": "secret_id",
	"google_firebase_hosting_site": "site_id",
	"google_artifact_registry_repository": "repository_id",
}

name_arg(t) := a if {
	a := name_args[t]
} else := "name"

# The types here that take labels, and where their labels sit (provider 5.x schema).
labels_of(r) := object.get(object.get(r.body, "settings", [{}])[0], "user_labels", {}) if {
	r.type == "google_sql_database_instance"
} else := object.get(r.body, "user_labels", {}) if {
	r.type in {"google_monitoring_alert_policy", "google_monitoring_uptime_check_config"}
}

labels_of(r) := object.get(r.body, "labels", {}) if {
	r.type in {
		"google_storage_bucket",
		"google_pubsub_topic",
		"google_cloudfunctions2_function",
		"google_cloud_run_v2_service",
		"google_cloud_run_v2_job",
		"google_secret_manager_secret",
		"google_artifact_registry_repository",
		"google_compute_global_address",
	}
}

env_label_values := {"${var.env}", "dev", "qa", "prod"}

env_checked contains r if {
	some r in resources
	not regex.match(`(^|/)local-only/`, r.path)
	not iam_db_user(r)
}

# ecofolk#1169: a Cloud SQL IAM database user's name is not chosen, it IS the service account's identity
# (<sa>@<project>.iam), so it can't carry var.env; the service account is what is per-environment. Only the
# CLOUD_IAM_SERVICE_ACCOUNT only is exempt (CLOUD_IAM_USER and CLOUD_IAM_GROUP are humans and groups): any other type, BUILT_IN included, is still checked.
iam_db_user(r) if {
	r.type == "google_sql_user"
	r.body.type == "CLOUD_IAM_SERVICE_ACCOUNT"
}

name_carries_env(v) if {
	is_string(v)
	regex.match(`\$\{[^}]*\b(var\.env|local\.env_suffix)\b`, v)
}

deny_env contains msg if {
	some r in env_checked
	arg := name_arg(r.type)
	v := r.body[arg]
	not name_carries_env(v)
	msg := sprintf("%s: %s must carry env (reference var.env or local.env_suffix, #13), got %v", [label(r), arg, v])
}

deny_env contains msg if {
	some r in env_checked
	labels := labels_of(r)
	not object.get(labels, "env", null) in env_label_values
	msg := sprintf("%s: must carry an env label (var.env, or dev, qa or prod; #13)", [label(r)])
}
