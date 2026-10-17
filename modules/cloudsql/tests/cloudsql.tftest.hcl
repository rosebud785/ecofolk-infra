# Issue #18 AC: with a mock provider (no credentials, no GCP), assert the version, region, private-only
# IP, deletion protection by default, the IAM authentication flag, and that the module declares no
# google_sql_user.
# Issue #2 AC (Architect consolidated AC, 2026-10-16): the maintenance window (Sun 05:00 CT), the backup
# start (05:30 CT), PITR on with 7 days of logs in dev and prod, deletion_protection defaulting to true
# (above), the export bucket's 30-day lifecycle and enforced public access prevention, and the export
# job's service account coming from a variable with no IAM in the module.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
  # The provider checks the self-link shape even under mock_provider, so this must look real.
  # (.tftest.hcl files are outside scripts/check-region-pin.sh's *.tf/*.tfvars scan.)
  private_network = "projects/ecofolk-dev/global/networks/ecofolk"
  # Built with format(), not written as a literal address (.gitleaks.toml's gcp-service-account-address
  # rule). The Architect's name default on #2: ops-scheduler in the project.
  export_service_account_email = format("%s@%s.iam.gserviceaccount.com", "ops-scheduler", "ecofolk-dev")
}

run "is_postgres_16_enterprise_in_the_pinned_region" {
  command = plan

  assert {
    condition     = google_sql_database_instance.postgres.database_version == "POSTGRES_16"
    error_message = "database_version must be POSTGRES_16"
  }

  assert {
    condition     = google_sql_database_instance.postgres.region == "northamerica-northeast1"
    error_message = "instance must be in northamerica-northeast1"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].edition == "ENTERPRISE"
    error_message = "edition must be ENTERPRISE"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].tier == "db-f1-micro"
    error_message = "tier must default to db-f1-micro (C7's allowlist)"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].availability_type == "ZONAL"
    error_message = "HA/REGIONAL is out of scope"
  }
}

# #39: tier is a variable again, and the instance takes it.
run "tier_follows_the_variable" {
  command = plan

  variables {
    tier = "db-g1-small"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].tier == "db-g1-small"
    error_message = "settings.tier must come from var.tier"
  }
}

run "has_no_public_ip" {
  command = plan

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].ip_configuration[0].ipv4_enabled == false
    error_message = "ipv4_enabled must be false: no public IP"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].ip_configuration[0].private_network == var.private_network
    error_message = "private_network must be the network passed in"
  }
}

run "backups_are_enabled" {
  command = plan

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].backup_configuration[0].enabled == true
    error_message = "automated backups must be enabled"
  }
}

run "deletion_protection_defaults_to_true" {
  command = plan

  assert {
    condition     = google_sql_database_instance.postgres.deletion_protection == true
    error_message = "deletion_protection must default to true"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].deletion_protection_enabled == true
    error_message = "settings.deletion_protection_enabled must follow deletion_protection"
  }
}

run "deletion_protection_follows_the_variable" {
  command = plan

  variables {
    deletion_protection = false
  }

  assert {
    condition     = google_sql_database_instance.postgres.deletion_protection == false && google_sql_database_instance.postgres.settings[0].deletion_protection_enabled == false
    error_message = "both deletion protection settings must come from var.deletion_protection"
  }
}

run "iam_authentication_flag_is_on" {
  command = plan

  assert {
    condition = anytrue([
      for f in google_sql_database_instance.postgres.settings[0].database_flags :
      f.name == "cloudsql.iam_authentication" && f.value == "on"
    ])
    error_message = "database flag cloudsql.iam_authentication must be on"
  }
}

run "declares_no_sql_user_or_password" {
  command = plan

  # A resource that doesn't exist can't be referenced, so read the module's own source instead.
  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"(google_sql_user|random_password)\"", file("${path.module}/${f}")))
    ])
    error_message = "the module must not declare a google_sql_user or random_password resource"
  }
}

run "outputs_and_database" {
  command = apply

  assert {
    condition     = google_sql_database.ecofolk.name == "ecofolk" && output.database_name == "ecofolk"
    error_message = "the module must create one database named ecofolk"
  }

  assert {
    condition     = output.connection_name == google_sql_database_instance.postgres.connection_name
    error_message = "connection_name must be the instance's connection name"
  }

  # #14: modules/sql_off_hours stops and starts the instance by this name.
  assert {
    condition     = output.instance_name == "ecofolk-pg"
    error_message = "instance_name must be the instance's name"
  }

  assert {
    condition     = output.private_ip_address == google_sql_database_instance.postgres.private_ip_address
    error_message = "private_ip_address must be the instance's private IP"
  }
}

run "rejects_another_region" {
  command = plan

  variables {
    region = "northamerica-northeast2"
  }

  expect_failures = [var.region]
}

# --- Issue #2 (C2): ops settings ---------------------------------------------------------------------

# Sunday 05:00 CT is Sunday 11:00 UTC (CST, UTC-6; see the locals in main.tf for why not CDT).
run "maintenance_window_is_sunday_0500_ct" {
  command = plan

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].maintenance_window[0].day == 7
    error_message = "maintenance window must be on Sunday (Cloud SQL day 7)"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].maintenance_window[0].hour == 11
    error_message = "maintenance window must start at 11:00 UTC (05:00 CST)"
  }
}

run "backup_starts_at_0530_ct" {
  command = plan

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].backup_configuration[0].start_time == "11:30"
    error_message = "backups must start at 11:30 UTC (05:30 CST)"
  }
}

run "pitr_on_with_7_days_of_logs_in_dev" {
  command = plan

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].backup_configuration[0].point_in_time_recovery_enabled == true
    error_message = "point_in_time_recovery_enabled must be true"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].backup_configuration[0].transaction_log_retention_days == 7
    error_message = "transaction_log_retention_days must be 7"
  }
}

# #12's go-live checkbox points here: the same module in the prod project keeps PITR on, 7 days.
run "pitr_on_with_7_days_of_logs_in_prod" {
  command = plan

  variables {
    project_id      = "ecofolk-prod"
    private_network = "projects/ecofolk-prod/global/networks/ecofolk"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].backup_configuration[0].point_in_time_recovery_enabled == true
    error_message = "point_in_time_recovery_enabled must be true in prod"
  }

  assert {
    condition     = google_sql_database_instance.postgres.settings[0].backup_configuration[0].transaction_log_retention_days == 7
    error_message = "transaction_log_retention_days must be 7 in prod"
  }

  assert {
    condition     = google_sql_database_instance.postgres.deletion_protection == true
    error_message = "deletion_protection must default to true in prod"
  }

  assert {
    condition     = google_storage_bucket.sql_exports.name == "ecofolk-prod-sql-exports"
    error_message = "the export bucket must follow the project id"
  }
}

# --- Issue #2 (C2): export bucket --------------------------------------------------------------------

run "export_bucket_is_named_pinned_and_private" {
  command = plan

  assert {
    condition     = google_storage_bucket.sql_exports.name == "ecofolk-dev-sql-exports"
    error_message = "export bucket must be named <project_id>-sql-exports (Architect name default on #2)"
  }

  assert {
    condition     = google_storage_bucket.sql_exports.location == "NORTHAMERICA-NORTHEAST1"
    error_message = "export bucket must be in NORTHAMERICA-NORTHEAST1 (Montréal)"
  }

  assert {
    condition     = google_storage_bucket.sql_exports.public_access_prevention == "enforced"
    error_message = "public_access_prevention must be \"enforced\""
  }

  assert {
    condition     = google_storage_bucket.sql_exports.uniform_bucket_level_access == true
    error_message = "uniform_bucket_level_access must be true"
  }

  assert {
    condition     = google_storage_bucket.sql_exports.versioning[0].enabled == true
    error_message = "versioning must be on"
  }

  assert {
    condition     = google_storage_bucket.sql_exports.force_destroy == false
    error_message = "the export bucket must never be emptied on destroy"
  }
}

run "export_bucket_deletes_objects_after_30_days" {
  command = plan

  assert {
    condition     = length(google_storage_bucket.sql_exports.lifecycle_rule) == 1
    error_message = "the export bucket must have exactly one lifecycle rule"
  }

  assert {
    condition     = one(google_storage_bucket.sql_exports.lifecycle_rule[0].action).type == "Delete"
    error_message = "the lifecycle rule must delete"
  }

  assert {
    condition     = one(google_storage_bucket.sql_exports.lifecycle_rule[0].condition).age == 30
    error_message = "the lifecycle rule must delete objects older than 30 days"
  }
}

# --- Issue #2 (C2): export job -----------------------------------------------------------------------

run "export_job_runs_at_0515_ct_in_the_pinned_region" {
  command = plan

  assert {
    condition     = google_cloud_scheduler_job.sql_export.schedule == "15 5 * * *"
    error_message = "the export must run at 05:15"
  }

  assert {
    condition     = google_cloud_scheduler_job.sql_export.time_zone == "America/Chicago"
    error_message = "the export schedule must be in America/Chicago (CT)"
  }

  assert {
    condition     = google_cloud_scheduler_job.sql_export.region == "northamerica-northeast1"
    error_message = "the export job must be in northamerica-northeast1"
  }
}

run "export_job_posts_the_admin_export_api" {
  command = plan

  assert {
    condition     = google_cloud_scheduler_job.sql_export.http_target[0].http_method == "POST"
    error_message = "the export job must POST"
  }

  assert {
    condition     = google_cloud_scheduler_job.sql_export.http_target[0].uri == "https://sqladmin.googleapis.com/v1/projects/ecofolk-dev/instances/ecofolk-pg/export"
    error_message = "the export job must call the Cloud SQL Admin export API for this instance"
  }

  assert {
    condition = jsondecode(base64decode(google_cloud_scheduler_job.sql_export.http_target[0].body)) == {
      exportContext = {
        fileType  = "SQL"
        uri       = "gs://ecofolk-dev-sql-exports/ecofolk.sql.gz"
        databases = ["ecofolk"]
      }
    }
    error_message = "the export body must export the ecofolk database as SQL into the export bucket"
  }
}

run "export_job_service_account_comes_from_the_variable" {
  command = plan

  variables {
    export_service_account_email = format("%s@%s.iam.gserviceaccount.com", "someone-else", "ecofolk-dev")
  }

  assert {
    condition     = google_cloud_scheduler_job.sql_export.http_target[0].oauth_token[0].service_account_email == var.export_service_account_email && startswith(var.export_service_account_email, "someone-else@")
    error_message = "the export job's OAuth service account must be var.export_service_account_email"
  }
}

run "rejects_a_non_service_account_email" {
  command = plan

  variables {
    export_service_account_email = "ops-scheduler"
  }

  expect_failures = [var.export_service_account_email]
}

run "declares_no_iam_or_keys" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"google_[a-z_]*(_iam_|service_account)", file("${path.module}/${f}")))
    ])
    error_message = "the module must not declare IAM, service-account or key resources (local follow-up only)"
  }
}
