# Issue #144 (Architect SPEC OK 2026-11-02): with mock providers (no credentials, no GCP), assert the prod
# composition's safety properties, which no other test covers (environments/prod had no tests/). Every run is a
# plan. Modules' internals are read through their outputs; what a plan cannot show (module blocks, region
# literals) is read from the source by tests/text_guards.
#
# Run by CI (tf-test) and locally:
#   terraform -chdir=environments/prod init -backend=false && terraform -chdir=environments/prod test
mock_provider "google" {}
mock_provider "google-beta" {}

# main.tf imports the Firebase project; a mock provider can't import, so the resource is overridden.
override_resource {
  target = module.web_hosting.google_firebase_project.this
}

# A mock would return a random string for the number; the real one is all digits.
override_data {
  target = data.google_project.this
  values = {
    number = "1234567890"
  }
}

# The service account emails are built with format() so no address literal sits in the file for the secret-scan
# gitleaks rules to flag (as in environments/dev/tests/internal_oidc.tftest.hcl).
variables {
  migrate_service_account_email       = format("%s@%s.iam.gserviceaccount.com", "migrate", "ecofolk-prod")
  sweep_invoker_service_account_email = format("%s@%s.iam.gserviceaccount.com", "invoker", "ecofolk-prod")
  alert_notification_channels         = ["projects/ecofolk-prod/notificationChannels/1234567890"]
  db_connection_failure_log_filter    = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.db_connect_failed\""
  media_write_failure_log_filter      = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.media_write_failed\""
  web_host                            = "app.example.org"
}

run "project_and_region_are_pinned" {
  command = plan

  assert {
    condition     = module.project.project_id == "ecofolk-prod"
    error_message = "the prod root must plan for project ecofolk-prod"
  }

  assert {
    condition     = output.project_region == "northamerica-northeast1"
    error_message = "the prod region pin must be northamerica-northeast1"
  }

  assert {
    condition     = output.cloudsql_protections.region == "northamerica-northeast1"
    error_message = "the Cloud SQL instance must plan in northamerica-northeast1"
  }
}

run "source_has_no_other_region_and_no_dev_only_module" {
  command = plan

  module {
    source = "./tests/text_guards"
  }

  variables {
    root_tf = [for f in sort(fileset(".", "*.tf")) : file(f)]
  }

  assert {
    condition     = length(setsubtract(toset(output.region_literals), toset(["northamerica-northeast1"]))) == 0
    error_message = "the prod source names a region other than northamerica-northeast1: ${jsonencode(output.region_literals)}"
  }

  assert {
    condition     = output.provider_sets_region == false
    error_message = "a provider block sets region; module.project's pin is the single source (ef#391)"
  }

  assert {
    condition     = !contains(output.module_blocks, "sql_off_hours") && !contains(output.module_blocks, "billing_killswitch")
    error_message = "prod must not call the dev-only modules sql_off_hours or billing_killswitch (they refuse a *-prod project)"
  }

  # Keeps the module-block regex from passing by matching nothing.
  assert {
    condition     = contains(output.module_blocks, "cloudsql") && contains(output.module_blocks, "auth") && length(output.module_blocks) >= 13
    error_message = "expected the prod composition's module blocks, found ${jsonencode(output.module_blocks)}"
  }
}

run "cloud_sql_is_protected_with_c2_windows" {
  command = plan

  assert {
    condition     = output.cloudsql_protections.deletion_protection == true && output.cloudsql_protections.deletion_protection_enabled == true
    error_message = "prod Cloud SQL must have deletion protection on, in Terraform and on the instance"
  }

  assert {
    condition     = output.cloudsql_protections.backup_enabled == true && output.cloudsql_protections.pitr_enabled == true && output.cloudsql_protections.transaction_log_days == 7
    error_message = "prod Cloud SQL must have backups and PITR on with 7 days of transaction logs"
  }

  assert {
    condition     = output.cloudsql_protections.maintenance_day == 7 && output.cloudsql_protections.maintenance_hour == 11 && output.cloudsql_protections.backup_start_time == "11:30"
    error_message = "C2's ops windows: maintenance Sunday 05:00 CT (7, 11 UTC), backup 05:30 CT (11:30 UTC)"
  }

  assert {
    condition     = length(module.cloudsql.export_job_name) > 0 && module.cloudsql.export_bucket_name == "ecofolk-prod-sql-exports" && length([for j in output.scheduler_jobs : j if j.name == module.cloudsql.export_job_name]) == 1
    error_message = "the nightly export (job and ecofolk-prod-sql-exports bucket) must be present in prod"
  }
}

run "auth_settings" {
  command = plan

  assert {
    condition     = output.authorized_domains == tolist(["localhost", "app.example.org"])
    error_message = "authorized_domains must be exactly localhost plus the prod web host, found ${jsonencode(output.authorized_domains)}"
  }
}

run "auth_domains_fall_back_to_hosting_site" {
  command = plan

  variables {
    web_host = null
  }

  assert {
    condition     = length(output.authorized_domains) == 2 && output.authorized_domains[0] == "localhost" && endswith(output.authorized_domains[1], ".web.app")
    error_message = "with web_host unset, authorized_domains is localhost plus the Hosting site host only"
  }
}

run "no_qa_or_dev_names" {
  command = plan

  assert {
    condition     = length(output.resource_names) > 30
    error_message = "resource_names should list the whole prod composition; it has ${length(output.resource_names)}"
  }

  assert {
    condition     = length([for n in output.resource_names : n if can(regex("-qa|_qa|dev", n))]) == 0
    error_message = "a prod resource name carries qa or dev: ${jsonencode([for n in output.resource_names : n if can(regex("-qa|_qa|dev", n))])}"
  }

  assert {
    condition     = length(output.scheduler_jobs) == 3
    error_message = "the prod composition should have 3 scheduler jobs (nightly export, idle-sit sweep, sync-usgs-water); update this count if a job was added on purpose"
  }
}
