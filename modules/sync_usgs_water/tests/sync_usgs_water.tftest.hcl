# Issue #98 AC (Architect's cloud spec, 2026-10-19): with a mock provider (no credentials, no GCP), assert
# the time zone is America/Chicago and that no run hour falls in 22–04, the hours #14's 22:15–04:45 CT dev
# Cloud SQL stop touches (docs/alerting-policy.md). Also: the schedule, the path, the oidc_token for the
# invoker with audience = the endpoint URL, no header and no oauth_token, the region pin, the outputs and
# every validation.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
  env        = "dev"
  api_url    = "https://api.example.test"
  # Built with format(), not written as a literal address (.gitleaks.toml's gcp-service-account-address
  # rule). The existing sweep invoker (#17), reused per the #98 spec.
  invoker_sa_email = format("%s@%s.iam.gserviceaccount.com", "sweep-invoker", "ecofolk-dev")
}

run "schedule_and_time_zone" {
  command = plan

  assert {
    condition     = google_cloud_scheduler_job.sync.time_zone == "America/Chicago"
    error_message = "the sync-usgs-water job's time zone must be America/Chicago"
  }

  assert {
    condition     = google_cloud_scheduler_job.sync.schedule == "0 5,11,17 * * *"
    error_message = "the sync-usgs-water job must run 0 5,11,17 * * * (ef PR #1105)"
  }

  assert {
    condition     = google_cloud_scheduler_job.sync.region == "northamerica-northeast1"
    error_message = "the sync-usgs-water job must be in northamerica-northeast1 (ef#391)"
  }

  assert {
    condition     = output.job_name == "sync-usgs-water"
    error_message = "job_name output must be sync-usgs-water"
  }

  assert {
    condition     = output.scheduler_jobs == [{ name = "sync-usgs-water", schedule = "0 5,11,17 * * *", time_zone = "America/Chicago" }]
    error_message = "scheduler_jobs must list exactly this job, for environments/dev's stop-window test (#99)"
  }
}

# The planned job's own schedule (not restated here), expanded by idle_sit_sweep's cron_hours helper, fires
# only in hours 05–21: none in 22, 23, 00, 01, 02, 03 or 04. An unreadable part expands to -1 and fails.
run "plan_for_hours" {
  command = plan
}

run "no_run_hour_in_22_to_04" {
  command = plan

  module {
    source = "../idle_sit_sweep/tests/cron_hours"
  }

  variables {
    schedule = run.plan_for_hours.scheduler_jobs[0].schedule
  }

  assert {
    condition     = toset(output.hours) == toset([5, 11, 17])
    error_message = "sync-usgs-water must fire at 05, 11 and 17 CT, got ${jsonencode(output.hours)}"
  }

  assert {
    condition     = length(output.hours) > 0 && alltrue([for h in output.hours : h >= 5 && h <= 21])
    error_message = "sync-usgs-water must not fire in hours 22–04 CT (dev Cloud SQL stop, #14): ${jsonencode(output.hours)}"
  }
}

# Known-wrong: the same check on a schedule with a 01:00 run sees hour 1, so the assertion above can fail.
run "known_wrong_one_am_is_caught" {
  command = plan

  module {
    source = "../idle_sit_sweep/tests/cron_hours"
  }

  variables {
    schedule = "0 1,5,11,17 * * *"
  }

  assert {
    condition     = !alltrue([for h in output.hours : h >= 5 && h <= 21])
    error_message = "a 01:00 run must fail the 22–04 hour check"
  }
}

run "posts_to_the_sync_path_on_api_url" {
  command = plan

  assert {
    condition     = google_cloud_scheduler_job.sync.http_target[0].http_method == "POST"
    error_message = "the job must POST"
  }

  assert {
    condition     = google_cloud_scheduler_job.sync.http_target[0].uri == "https://api.example.test/internal/sync-usgs-water"
    error_message = "the job must call {api_url}/internal/sync-usgs-water"
  }
}

run "oidc_token_for_the_invoker_with_the_endpoint_audience" {
  command = plan

  assert {
    condition     = length(google_cloud_scheduler_job.sync.http_target[0].oidc_token) == 1
    error_message = "the job must carry exactly one oidc_token block"
  }

  assert {
    condition     = google_cloud_scheduler_job.sync.http_target[0].oidc_token[0].audience == google_cloud_scheduler_job.sync.http_target[0].uri
    error_message = "the oidc_token audience must be the same string as the job's uri"
  }

  assert {
    condition     = google_cloud_scheduler_job.sync.http_target[0].oidc_token[0].service_account_email == var.invoker_sa_email
    error_message = "the oidc_token must be minted for var.invoker_sa_email"
  }

  assert {
    condition     = output.audience == "https://api.example.test/internal/sync-usgs-water"
    error_message = "the audience output must equal the endpoint URL"
  }
}

run "no_oauth_token_and_no_header" {
  command = plan

  assert {
    condition     = length(google_cloud_scheduler_job.sync.http_target[0].oauth_token) == 0
    error_message = "the job must have no oauth_token block (oidc_token only)"
  }

  assert {
    condition     = length(coalesce(google_cloud_scheduler_job.sync.http_target[0].headers, {})) == 0
    error_message = "Terraform must set no header on the job; the OIDC token is the only credential"
  }
}

run "rejects_another_region" {
  command = plan

  variables {
    region = "northamerica-northeast2"
  }

  expect_failures = [var.region]
}

run "rejects_an_http_api_url" {
  command = plan

  variables {
    api_url = "http://api.example.test"
  }

  expect_failures = [var.api_url]
}

run "rejects_an_api_url_with_a_trailing_slash" {
  command = plan

  variables {
    api_url = "https://api.example.test/"
  }

  expect_failures = [var.api_url]
}

run "rejects_an_invoker_that_is_not_a_service_account" {
  command = plan

  variables {
    invoker_sa_email = format("%s@%s", "sweep-invoker", "example.test")
  }

  expect_failures = [var.invoker_sa_email]
}

# Issue #13: env. dev keeps the job name; qa would get -qa.

run "env_dev_keeps_its_names_and_labels" {
  command = plan

  assert {
    condition     = google_cloud_scheduler_job.sync.name == "sync-usgs-water"
    error_message = "dev must keep the job name sync-usgs-water"
  }

  assert {
    condition     = output.resource_names == ["google_cloud_scheduler_job/sync-usgs-water"]
    error_message = "resource_names must be every name the module sets (#13), got ${jsonencode(output.resource_names)}"
  }
}

run "env_qa_suffixes_names_and_labels" {
  command = plan

  variables {
    env = "qa"
  }

  assert {
    condition     = google_cloud_scheduler_job.sync.name == "sync-usgs-water-qa"
    error_message = "qa must name the job sync-usgs-water-qa"
  }

  assert {
    condition     = output.resource_names == ["google_cloud_scheduler_job/sync-usgs-water-qa"]
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
