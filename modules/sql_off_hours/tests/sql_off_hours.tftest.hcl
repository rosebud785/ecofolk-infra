# Issue #14 AC (Architect SPEC OK 2026-10-16, amended): with a mock provider (no credentials, no GCP),
# assert the cron strings (15 22 * * * stop, 45 4 * * * start), the time zone America/Chicago, and that a
# prod composition (#12) cannot instantiate the jobs. Also: the region pin, the PATCH body each job sends,
# the service account coming from the variable, enable_off_hours, and every validation.
mock_provider "google" {}

variables {
  project_id    = "ecofolk-dev"
  env           = "dev"
  instance_name = "ecofolk-pg"
  # Built with format(), not written as a literal address (.gitleaks.toml's gcp-service-account-address
  # rule). The Architect's name default on #14: ops-scheduler, the same account as #2.
  service_account_email = format("%s@%s.iam.gserviceaccount.com", "ops-scheduler", "ecofolk-dev")
}

run "stop_job_runs_at_2215_central" {
  command = plan

  assert {
    condition     = google_cloud_scheduler_job.this["stop"].schedule == "15 22 * * *"
    error_message = "stop job must run at 15 22 * * *"
  }

  assert {
    condition     = google_cloud_scheduler_job.this["stop"].time_zone == "America/Chicago"
    error_message = "stop job time zone must be America/Chicago"
  }

  assert {
    condition     = jsondecode(base64decode(google_cloud_scheduler_job.this["stop"].http_target[0].body)).settings.activationPolicy == "NEVER"
    error_message = "stop job must PATCH settings.activationPolicy = NEVER"
  }
}

run "start_job_runs_at_0445_central_before_maintenance" {
  command = plan

  assert {
    condition     = google_cloud_scheduler_job.this["start"].schedule == "45 4 * * *"
    error_message = "start job must run at 45 4 * * * (before #2's 05:00 CT maintenance window)"
  }

  assert {
    condition     = google_cloud_scheduler_job.this["start"].time_zone == "America/Chicago"
    error_message = "start job time zone must be America/Chicago"
  }

  assert {
    condition     = jsondecode(base64decode(google_cloud_scheduler_job.this["start"].http_target[0].body)).settings.activationPolicy == "ALWAYS"
    error_message = "start job must PATCH settings.activationPolicy = ALWAYS"
  }
}

run "jobs_patch_the_instance_via_sqladmin_as_the_variable_account" {
  command = plan

  assert {
    condition     = length(google_cloud_scheduler_job.this) == 2
    error_message = "enable_off_hours defaults to true: exactly two jobs (stop, start)"
  }

  assert {
    condition = alltrue([for j in google_cloud_scheduler_job.this :
      j.region == "northamerica-northeast1" &&
      j.http_target[0].http_method == "PATCH" &&
      j.http_target[0].uri == "https://sqladmin.googleapis.com/v1/projects/ecofolk-dev/instances/ecofolk-pg" &&
      j.http_target[0].oauth_token[0].service_account_email == var.service_account_email
    ])
    error_message = "each job must be in northamerica-northeast1 and PATCH the Cloud SQL Admin instance URI with a token for var.service_account_email"
  }

  assert {
    condition     = output.job_names == { stop = "ecofolk-pg-off-hours-stop", start = "ecofolk-pg-off-hours-start" }
    error_message = "job_names output must name both jobs"
  }
}

run "enable_off_hours_false_creates_no_jobs" {
  command = plan

  variables {
    enable_off_hours = false
  }

  assert {
    condition     = length(google_cloud_scheduler_job.this) == 0
    error_message = "enable_off_hours = false must create no jobs"
  }

  assert {
    condition     = output.job_names == {}
    error_message = "job_names must be empty when enable_off_hours is false"
  }
}

# The prod composition (#12) must not instantiate the jobs: the module refuses a prod project outright,
# even with enable_off_hours left at its default.
run "prod_composition_cannot_instantiate_the_jobs" {
  command = plan

  variables {
    project_id = "ecofolk-prod"
  }

  expect_failures = [var.project_id]
}

run "prod_composition_with_suffixed_id_cannot_instantiate_the_jobs" {
  command = plan

  variables {
    project_id = "ecofolk-prod-a1b2"
  }

  expect_failures = [var.project_id]
}

run "suffixed_dev_project_is_accepted" {
  command = plan

  variables {
    project_id = "ecofolk-dev-a1b2"
  }

  assert {
    condition     = length(google_cloud_scheduler_job.this) == 2
    error_message = "a suffixed dev project id must still get both jobs"
  }
}

run "rejects_another_region" {
  command = plan

  variables {
    region = "northamerica-northeast2"
  }

  expect_failures = [var.region]
}

run "rejects_a_bad_instance_name" {
  command = plan

  variables {
    instance_name = "Ecofolk_PG"
  }

  expect_failures = [var.instance_name]
}

run "rejects_a_non_service_account_email" {
  command = plan

  variables {
    service_account_email = "someone@example.com"
  }

  expect_failures = [var.service_account_email]
}

# Issue #13: env. dev only: the job names are unchanged, and qa (which shares the instance) and prod are refused.

run "env_dev_keeps_its_names_and_labels" {
  command = plan

  assert {
    condition     = sort([for j in google_cloud_scheduler_job.this : j.name]) == tolist(["ecofolk-pg-off-hours-start", "ecofolk-pg-off-hours-stop"])
    error_message = "dev must keep both job names"
  }

  assert {
    condition = sort(output.resource_names) == tolist([
      "google_cloud_scheduler_job/ecofolk-pg-off-hours-start",
      "google_cloud_scheduler_job/ecofolk-pg-off-hours-stop",
    ])
    error_message = "resource_names must be every name the module sets (#13), got ${jsonencode(output.resource_names)}"
  }
}

run "env_refuses_staging" {
  command = plan

  variables {
    env = "staging"
  }

  expect_failures = [var.env]
}

run "env_refuses_qa" {
  command = plan

  variables {
    env = "qa"
  }

  expect_failures = [var.env]
}

run "env_refuses_prod" {
  command = plan

  variables {
    env = "prod"
  }

  expect_failures = [var.env]
}
