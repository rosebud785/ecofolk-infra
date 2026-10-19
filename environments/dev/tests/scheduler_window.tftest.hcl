# Issue #99 (Architect's ruling on #97): with mock providers (no credentials, no GCP), every Cloud Scheduler
# job in the composed dev plan is America/Chicago and has no run while #14 has dev Cloud SQL stopped, after
# 22:15 and before 04:45 CT. The stop (22:15) and start (04:45) jobs sit on the window's edges and pass.
#
# The jobs come from the root output scheduler_jobs, which concatenates each module's scheduler_jobs output
# (a test can read module outputs, not resources inside modules). dev_plan also fails if a module this root
# calls declares a google_cloud_scheduler_job but isn't in that output, so a new job can't skip the check.
#
# Not run by CI: the tf-test job only tests modules/*. Run it locally:
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

run "dev_plan" {
  command = plan

  assert {
    condition     = length(output.scheduler_jobs) == 4
    error_message = "the dev composition should have 4 scheduler jobs (nightly export, off-hours stop and start, idle-sit sweep); update this count if a job was added on purpose"
  }
}

# Every module called from main.tf whose source declares a google_cloud_scheduler_job must be in the
# scheduler_jobs output, and the root declares none itself.
run "every_scheduler_module_is_in_the_output" {
  command = plan

  module {
    source = "./tests/scheduler_coverage"
  }

  variables {
    main_tf = file("main.tf")
    root_tf = [for f in sort(fileset(".", "*.tf")) : file(f)]
    module_sources = {
      for d in distinct([for f in fileset("../../modules", "*/*.tf") : dirname(f)]) :
      d => join("\n", [for f in sort(fileset("../../modules/${d}", "*.tf")) : file("../../modules/${d}/${f}")])
    }
  }

  # Keeps the call regex from passing by matching nothing.
  assert {
    condition     = output.modules_with_jobs == tolist(["cloudsql", "idle_sit_sweep", "sql_off_hours"])
    error_message = "expected the cloudsql, idle_sit_sweep and sql_off_hours module calls to carry scheduler jobs, found ${jsonencode(output.modules_with_jobs)}; if a module was added on purpose, add it here and to the scheduler_jobs output"
  }

  assert {
    condition     = length(output.uncovered) == 0
    error_message = "module calls declare a google_cloud_scheduler_job but aren't in environments/dev's scheduler_jobs output: ${join(", ", output.uncovered)} (#99)"
  }

  assert {
    condition     = !output.root_declares_jobs
    error_message = "declare scheduler jobs in a module that exposes scheduler_jobs, not in environments/dev itself (#99)"
  }
}

run "every_job_central_and_outside_the_stop" {
  command = plan

  module {
    source = "./tests/scheduler_window"
  }

  variables {
    jobs = run.dev_plan.scheduler_jobs
  }

  assert {
    condition     = output.job_count == 4
    error_message = "the checker must see all 4 dev scheduler jobs"
  }

  assert {
    condition     = length(output.violations) == 0
    error_message = "dev scheduler jobs break the America/Chicago / 22:15–04:45 CT invariant: ${join("; ", output.violations)}"
  }
}

# The checker itself, on the issue's known-wrongs and the window's edges.
run "known_wrong_no_time_zone_is_red" {
  command = plan

  module {
    source = "./tests/scheduler_window"
  }

  variables {
    jobs = [{ name = "no-tz", schedule = "0 12 * * *", time_zone = null }]
  }

  assert {
    condition     = length(output.violations) == 1 && strcontains(output.violations[0], "time_zone is unset")
    error_message = "a job with no time_zone must be a violation"
  }
}

run "known_wrong_one_am_central_is_red" {
  command = plan

  module {
    source = "./tests/scheduler_window"
  }

  variables {
    jobs = [{ name = "one-am", schedule = "0 1 * * *", time_zone = "America/Chicago" }]
  }

  assert {
    condition     = length(output.violations) == 1 && strcontains(output.violations[0], "fires at 01:00 CT")
    error_message = "a job at 0 1 * * * America/Chicago must be a violation"
  }
}

run "known_right_four_fifty_central_is_green" {
  command = plan

  module {
    source = "./tests/scheduler_window"
  }

  variables {
    jobs = [{ name = "four-fifty", schedule = "50 4 * * *", time_zone = "America/Chicago" }]
  }

  assert {
    condition     = length(output.violations) == 0
    error_message = "a job at 50 4 * * * America/Chicago is just outside the window and must pass"
  }
}

run "window_edges" {
  command = plan

  module {
    source = "./tests/scheduler_window"
  }

  variables {
    jobs = [
      { name = "stop", schedule = "15 22 * * *", time_zone = "America/Chicago" },
      { name = "start", schedule = "45 4 * * *", time_zone = "America/Chicago" },
      { name = "after-stop", schedule = "16 22 * * *", time_zone = "America/Chicago" },
      { name = "before-start", schedule = "44 4 * * *", time_zone = "America/Chicago" },
      { name = "module-default", schedule = "0 */2 * * *", time_zone = "America/Chicago" },
      { name = "utc", schedule = "0 12 * * *", time_zone = "Etc/UTC" },
      { name = "unreadable", schedule = "@daily", time_zone = "America/Chicago" },
    ]
  }

  assert {
    condition = [for v in output.violations : split(":", v)[0]] == [
      "after-stop", "before-start", "module-default", "utc", "unreadable",
    ]
    error_message = "only the 22:15 stop and 04:45 start edges may pass: ${join("; ", output.violations)}"
  }
}
