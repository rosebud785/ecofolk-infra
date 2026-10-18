# Issue #17 AC (Architect respec 2026-10-16, amended the same day): with a mock provider (no credentials,
# no GCP), assert the schedule, the time zone and the path, that there's no oidc_token block, that no .tf
# file in the module mentions the sweep credential or its header, and that the dev composition's schedule
# only fires inside 05–22 CT. Also: the region pin, no oauth_token, no header in config, the output, and
# every validation.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
  api_url    = "https://api.example.test"
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

run "no_google_token_and_no_header_in_config" {
  command = plan

  assert {
    condition     = length(google_cloud_scheduler_job.sweep.http_target[0].oidc_token) == 0
    error_message = "the sweep job must have no oidc_token block (it would collide with the API's bearer header)"
  }

  assert {
    condition     = length(google_cloud_scheduler_job.sweep.http_target[0].oauth_token) == 0
    error_message = "the sweep job must have no oauth_token block"
  }

  assert {
    condition     = length(coalesce(google_cloud_scheduler_job.sweep.http_target[0].headers, {})) == 0
    error_message = "Terraform must set no header on the sweep job; the header is set out of band"
  }
}

# The grep AC: no *.tf file anywhere under the module (this helper's included) names the credential or
# its header, in any case. The pattern lives here, in a .tftest.hcl, so the check never matches itself.
run "no_tf_file_mentions_the_credential_or_its_header" {
  command = plan

  assert {
    condition     = length(fileset(path.module, "**/*.tf")) >= 4
    error_message = "the grep found too few *.tf files; it isn't looking at the module"
  }

  assert {
    condition = alltrue([
      for f in fileset(path.module, "**/*.tf") :
      !can(regex("(?i)(sweep_token|authorization)", file("${path.module}/${f}")))
    ])
    error_message = "a *.tf file in modules/idle_sit_sweep mentions SWEEP_TOKEN or Authorization"
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
