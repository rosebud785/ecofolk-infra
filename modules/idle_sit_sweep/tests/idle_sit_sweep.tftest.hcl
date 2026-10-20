# Issue #17 AC (Architect's OIDC redesign on PR #86, 2026-10-18, over the 10-16 respec and amendment): with
# a mock provider (no credentials, no GCP), assert the schedule, the time zone and the path; that the job
# carries an oidc_token minted for invoker_sa_email whose audience equals the endpoint URL; that no header
# is set in Terraform; that the old static sweep credential is named nowhere, and its header only in
# README prose; and that the dev composition's schedule fires only inside 05–22 CT. Also: the region pin,
# no oauth_token, the outputs, and every validation.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
  env        = "dev"
  api_url    = "https://api.example.test"
  # Built with format(), not written as a literal address (.gitleaks.toml's gcp-service-account-address
  # rule). The Architect's name on #17: sweep-invoker.
  invoker_sa_email = format("%s@%s.iam.gserviceaccount.com", "sweep-invoker", "ecofolk-dev")
}

run "default_schedule_is_every_two_hours_central" {
  command = plan

  assert {
    condition     = google_cloud_scheduler_job.sweep.schedule == "0 */2 * * *"
    error_message = "sweep_schedule must default to 0 */2 * * * (every 2 hours, under the 3h threshold)"
  }

  assert {
    condition     = google_cloud_scheduler_job.sweep.time_zone == "America/Chicago"
    error_message = "the sweep's time zone must be America/Chicago"
  }

  assert {
    condition     = google_cloud_scheduler_job.sweep.region == "northamerica-northeast1"
    error_message = "the sweep job must be in northamerica-northeast1 (ef#391)"
  }

  assert {
    condition     = output.job_name == "idle-sit-sweep"
    error_message = "job_name output must be idle-sit-sweep"
  }
}

run "posts_to_the_sweep_path_on_api_url" {
  command = plan

  assert {
    condition     = google_cloud_scheduler_job.sweep.http_target[0].http_method == "POST"
    error_message = "the sweep must POST"
  }

  assert {
    condition     = google_cloud_scheduler_job.sweep.http_target[0].uri == "https://api.example.test/internal/sweep-idle-sits"
    error_message = "the sweep must call {api_url}/internal/sweep-idle-sits"
  }
}

run "oidc_token_audience_is_the_endpoint_url" {
  command = plan

  assert {
    condition     = length(google_cloud_scheduler_job.sweep.http_target[0].oidc_token) == 1
    error_message = "the sweep job must carry exactly one oidc_token block"
  }

  assert {
    condition     = google_cloud_scheduler_job.sweep.http_target[0].oidc_token[0].audience == "https://api.example.test/internal/sweep-idle-sits"
    error_message = "the oidc_token audience must equal the endpoint URL, {api_url}/internal/sweep-idle-sits"
  }

  assert {
    condition     = google_cloud_scheduler_job.sweep.http_target[0].oidc_token[0].audience == google_cloud_scheduler_job.sweep.http_target[0].uri
    error_message = "the oidc_token audience must be the same string as the job's uri"
  }

  assert {
    condition     = google_cloud_scheduler_job.sweep.http_target[0].oidc_token[0].service_account_email == var.invoker_sa_email
    error_message = "the oidc_token must be minted for var.invoker_sa_email"
  }

  assert {
    condition     = output.audience == "https://api.example.test/internal/sweep-idle-sits"
    error_message = "the audience output must equal the endpoint URL"
  }
}

run "no_oauth_token_and_no_header_in_config" {
  command = plan

  assert {
    condition     = length(google_cloud_scheduler_job.sweep.http_target[0].oauth_token) == 0
    error_message = "the sweep job must have no oauth_token block (oidc_token only)"
  }

  assert {
    condition     = length(coalesce(google_cloud_scheduler_job.sweep.http_target[0].headers, {})) == 0
    error_message = "Terraform must set no header on the sweep job; the OIDC token is the only credential"
  }
}

# The grep ACs. Scanned: every file in this module (tests included, .terraform/ and the lock file not)
# plus the env roots' *.tf. The patterns are written with a [x] class, so this file never matches itself.
#   - the old static credential's name appears in none of them, README included;
#   - the header name appears only in this module's README.md (prose), in no other scanned file;
#   - no lifecycle ignore_changes is left in the module's *.tf (Terraform owns the whole job).
run "grep_static_credential_and_header" {
  command = plan

  assert {
    condition = length([
      for f in concat(tolist(fileset(path.module, "**/*.tf")), tolist(fileset("${path.module}/../../environments", "*/*.tf"))) : f
      if !startswith(f, ".terraform")
    ]) >= 7
    error_message = "the grep found too few *.tf files; it isn't looking at the module and env roots"
  }

  assert {
    condition     = fileexists("${path.module}/README.md")
    error_message = "the grep expects modules/idle_sit_sweep/README.md"
  }

  assert {
    condition = alltrue(concat(
      [for f in fileset(path.module, "**") : !can(regex("(?i)sweep[_]token", file("${path.module}/${f}"))) if !startswith(f, ".terraform")],
      [for f in fileset("${path.module}/../../environments", "*/*.tf") : !can(regex("(?i)sweep[_]token", file("${path.module}/../../environments/${f}")))],
    ))
    error_message = "a scanned file names the old static sweep credential"
  }

  assert {
    condition = alltrue(concat(
      [for f in fileset(path.module, "**") : !can(regex("(?i)authori[z]ation", file("${path.module}/${f}"))) if !startswith(f, ".terraform") && f != "README.md"],
      [for f in fileset("${path.module}/../../environments", "*/*.tf") : !can(regex("(?i)authori[z]ation", file("${path.module}/../../environments/${f}")))],
    ))
    error_message = "the request header's name appears outside modules/idle_sit_sweep/README.md"
  }

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") : !can(regex("ignore[_]changes\\s*=", file("${path.module}/${f}")))
    ])
    error_message = "modules/idle_sit_sweep must not ignore_changes on the job (Terraform owns it)"
  }
}

run "custom_schedule_is_passed_through" {
  command = plan

  variables {
    sweep_schedule = "30 6 * * 1-5"
  }

  assert {
    condition     = google_cloud_scheduler_job.sweep.schedule == "30 6 * * 1-5"
    error_message = "sweep_schedule must be passed through to the job"
  }
}

# Amendment AC: the schedule environments/dev actually passes (read from its main.tf, not restated here)
# fires only in hours 05–21 CT, so every run starts at or after 05:00 and before 22:00, outside #14's
# 22:15–04:45 stop.
run "dev_schedule_hours" {
  command = plan

  module {
    source = "./tests/cron_hours"
  }

  variables {
    schedule = regex("sweep_schedule\\s*=\\s*\"([^\"]+)\"", file("../../environments/dev/main.tf"))[0]
  }

  assert {
    condition     = var.schedule == "0 5-21/2 * * *"
    error_message = "environments/dev must pass sweep_schedule = \"0 5-21/2 * * *\" (Architect amendment on #17)"
  }

  assert {
    condition     = length(output.hours) > 0 && alltrue([for h in output.hours : h >= 5 && h <= 21])
    error_message = "the dev sweep schedule must fire only in hours 05–21 CT (inside 05–22, while dev Cloud SQL runs)"
  }
}

# The helper itself goes red on schedules that leave the window, so the check above can fail.
run "cron_hours_helper_catches_overnight_hours" {
  command = plan

  module {
    source = "./tests/cron_hours"
  }

  variables {
    schedule = "0 */2 * * *"
  }

  assert {
    condition     = contains(output.hours, 0) && contains(output.hours, 22) && length(output.hours) == 12
    error_message = "0 */2 * * * must expand to the 12 even hours, 0 and 22 included"
  }
}

run "cron_hours_helper_expands_lists_and_ranges" {
  command = plan

  module {
    source = "./tests/cron_hours"
  }

  variables {
    schedule = "0 5,7-8,20-23/3 * * *"
  }

  assert {
    condition     = toset(output.hours) == toset([5, 7, 8, 20, 23])
    error_message = "5,7-8,20-23/3 must expand to 5, 7, 8, 20, 23"
  }
}

run "cron_hours_helper_flags_an_unreadable_part" {
  command = plan

  module {
    source = "./tests/cron_hours"
  }

  variables {
    schedule = "0 H * * *"
  }

  assert {
    condition     = contains(output.hours, -1)
    error_message = "an unreadable hour part must expand to -1"
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

run "rejects_a_schedule_without_five_fields" {
  command = plan

  variables {
    sweep_schedule = "*/2 * * *"
  }

  expect_failures = [var.sweep_schedule]
}

run "rejects_an_invoker_that_is_not_a_service_account" {
  command = plan

  variables {
    invoker_sa_email = format("%s@%s", "sweep-invoker", "example.test")
  }

  expect_failures = [var.invoker_sa_email]
}

run "rejects_a_lookalike_domain" {
  command = plan

  variables {
    invoker_sa_email = format("%s@%s", "sweep-invoker", "ecofolk-dev.iam.gserviceaccount.com.example.test")
  }

  expect_failures = [var.invoker_sa_email]
}

# Issue #13: env. dev keeps the job name; qa would get -qa.

run "env_dev_keeps_its_names_and_labels" {
  command = plan

  assert {
    condition     = google_cloud_scheduler_job.sweep.name == "idle-sit-sweep"
    error_message = "dev must keep the job name idle-sit-sweep"
  }

  assert {
    condition     = output.resource_names == ["google_cloud_scheduler_job/idle-sit-sweep"]
    error_message = "resource_names must be every name the module sets (#13), got ${jsonencode(output.resource_names)}"
  }
}

run "env_qa_suffixes_names_and_labels" {
  command = plan

  variables {
    env = "qa"
  }

  assert {
    condition     = google_cloud_scheduler_job.sweep.name == "idle-sit-sweep-qa"
    error_message = "qa must name the job idle-sit-sweep-qa"
  }

  assert {
    condition     = output.resource_names == ["google_cloud_scheduler_job/idle-sit-sweep-qa"]
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
