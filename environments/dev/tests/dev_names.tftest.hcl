# Issue #13 safety AC (Architect, c6296156436; ruling c6316927286, point 2): threading env through every
# module must leave dev's existing names byte-identical, since a renamed resource is a destroy-and-create on
# the push-to-main apply (for the Cloud SQL instance, data loss). With mock providers (no credentials, no GCP),
# this plans the WHOLE dev composition and asserts those names as literals: the Cloud SQL instance, the Cloud
# Run service, the buckets and the four secret ids.
#
# The per-module env_dev_keeps_its_names_and_labels runs don't replace this: they can't see a dev root that
# passes a different env, or drops one. Every literal below is the name dev has today; never derive it.
#
# Not run by CI until #107 (PR #129): the tf-test job only tests modules/*. Run it locally:
#   terraform -chdir=environments/dev init -backend=false && terraform -chdir=environments/dev test
mock_provider "google" {}
mock_provider "google-beta" {}

# main.tf imports the Firebase project; a mock provider can't import, so the resource is overridden.
override_resource {
  target = module.web_hosting.google_firebase_project.this
}

variables {
  project_id                       = "ecofolk-dev"
  alert_notification_channels      = ["projects/ecofolk-dev/notificationChannels/1234567890"]
  db_connection_failure_log_filter = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.db_connect_failed\""
  media_write_failure_log_filter   = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.media_write_failed\""
}

run "dev_keeps_its_existing_names" {
  command = plan

  assert {
    condition     = module.cloudsql.instance_name == "ecofolk-pg"
    error_message = "the dev Cloud SQL instance must stay ecofolk-pg (a rename replaces it: data loss), got ${module.cloudsql.instance_name}"
  }

  assert {
    condition     = module.cloudrun_api.name == "ecofolk-api"
    error_message = "the dev Cloud Run service must stay ecofolk-api, got ${module.cloudrun_api.name}"
  }

  assert {
    condition     = module.cloudsql.export_bucket_name == "ecofolk-dev-sql-exports"
    error_message = "the dev export bucket must stay ecofolk-dev-sql-exports, got ${module.cloudsql.export_bucket_name}"
  }

  assert {
    condition     = module.media_bucket.bucket_name == "ecofolk-dev-media"
    error_message = "the dev media bucket must stay ecofolk-dev-media, got ${module.media_bucket.bucket_name}"
  }

  assert {
    condition = alltrue([for n in [
      "google_sql_database_instance/ecofolk-pg",
      "google_cloud_run_v2_service/ecofolk-api",
      "google_storage_bucket/ecofolk-dev-sql-exports",
      "google_storage_bucket/ecofolk-dev-media",
      "google_storage_bucket/ecofolk-dev-killswitch-src",
      "google_secret_manager_secret/POSTGRES_PASSWORD",
      "google_secret_manager_secret/POSTGRES_INGEST_PASSWORD",
      "google_secret_manager_secret/NOAA_CDO_TOKEN",
      "google_secret_manager_secret/SWEEP_TOKEN",
    ] : contains(output.resource_names, n)])
    error_message = "dev's composition must keep its existing instance, service, bucket and secret names, got ${jsonencode(output.resource_names)}"
  }

  # Exactly three buckets and four secrets: no suffixed copy next to the original.
  assert {
    condition = (
      sort([for n in output.resource_names : n if startswith(n, "google_storage_bucket/")]) == sort([
        "google_storage_bucket/ecofolk-dev-killswitch-src",
        "google_storage_bucket/ecofolk-dev-media",
        "google_storage_bucket/ecofolk-dev-sql-exports",
      ]) &&
      sort([for n in output.resource_names : n if startswith(n, "google_secret_manager_secret/")]) == sort([
        "google_secret_manager_secret/NOAA_CDO_TOKEN",
        "google_secret_manager_secret/POSTGRES_INGEST_PASSWORD",
        "google_secret_manager_secret/POSTGRES_PASSWORD",
        "google_secret_manager_secret/SWEEP_TOKEN",
      ])
    )
    error_message = "dev must have exactly its three existing buckets and four secret ids, got ${jsonencode(output.resource_names)}"
  }
}

# ecofolk#1169: the migrate job is named ecofolk-migrate, runs as the keyless migrate SA on the API's subnet,
# and that SA is the Cloud SQL IAM database user (so the job's DB identity can't drift from the user Terraform
# creates). Literals, as above: never derive them.
run "migrate_job_wiring" {
  command = plan

  assert {
    condition     = module.migrate_job.name == "ecofolk-migrate"
    error_message = "the dev migrate job must be ecofolk-migrate, got ${module.migrate_job.name}"
  }

  assert {
    condition     = module.migrate_job.env_vars["DB_IAM_USER"] == format("%s@%s.iam", "ecofolk-migrate", "ecofolk-dev")
    error_message = "the job's DB_IAM_USER must be the migrate SA's IAM database user name"
  }

  assert {
    condition     = contains(module.cloudsql.resource_names, format("google_sql_user/%s@%s.iam", "ecofolk-migrate", "ecofolk-dev"))
    error_message = "module.cloudsql must create the migrate SA's IAM database user"
  }
}
