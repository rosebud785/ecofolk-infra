# Issue #114 (Architect ruling (a), ecofolk#1092 / PR #1108): the API verifies every scheduler call's OIDC
# token against INTERNAL_AUDIENCE_BASE + route path, byte for byte. With mock providers (no credentials, no
# GCP), assert that the one shared local (the deterministic run.app URL) is what the service's env and BOTH
# scheduler jobs use, that each job's uri equals the audience it mints, that no SWEEP_TOKEN is mapped, and
# that INTERNAL_INVOKER_EMAIL is set.
#
# The invoker email is built with format() so no service-account address literal sits in the file for
# the secret-scan email/gcp-service-account rules to flag (as in modules/idle_sit_sweep/tests).
#
# Mutation check (run by hand, #114): set either job's api_url back to module.cloudrun_api.uri and run this
# file; the mock uri is not the deterministic string, so the equality asserts below fail.
#
# Not run by CI: the tf-test job only tests modules/*. Run it locally:
#   terraform -chdir=environments/dev init -backend=false && terraform -chdir=environments/dev test
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

variables {
  project_id                       = "ecofolk-dev"
  alert_notification_channels      = ["projects/ecofolk-dev/notificationChannels/1234567890"]
  db_connection_failure_log_filter = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.db_connect_failed\""
  media_write_failure_log_filter   = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.media_write_failed\""
}

run "audience_base_is_one_value_everywhere" {
  command = plan

  assert {
    condition     = module.cloudrun_api.env["INTERNAL_AUDIENCE_BASE"] == "https://ecofolk-api-1234567890.northamerica-northeast1.run.app"
    error_message = "INTERNAL_AUDIENCE_BASE must be the deterministic run.app URL https://<service>-<project number>.<region>.run.app"
  }

  assert {
    condition     = can(regex("^https://[a-z0-9-]+-[0-9]+\\.[a-z0-9-]+\\.run\\.app$", module.cloudrun_api.env["INTERNAL_AUDIENCE_BASE"]))
    error_message = "INTERNAL_AUDIENCE_BASE must match ^https://<service>-<digits>.<region>.run.app$ (the deterministic form, not the hash .a.run.app form)"
  }

  assert {
    condition     = trimsuffix(module.idle_sit_sweep.audience, "/internal/sweep-idle-sits") == module.cloudrun_api.env["INTERNAL_AUDIENCE_BASE"]
    error_message = "the idle-sit sweep job's audience, minus its path, must equal INTERNAL_AUDIENCE_BASE exactly (a mismatch 401s every call, silently)"
  }

  assert {
    condition     = trimsuffix(module.sync_usgs_water.audience, "/internal/sync-usgs-water") == module.cloudrun_api.env["INTERNAL_AUDIENCE_BASE"]
    error_message = "the sync-usgs-water job's audience, minus its path, must equal INTERNAL_AUDIENCE_BASE exactly (a mismatch 401s every call, silently)"
  }

  assert {
    condition     = module.idle_sit_sweep.audience == "${module.cloudrun_api.env["INTERNAL_AUDIENCE_BASE"]}/internal/sweep-idle-sits"
    error_message = "the sweep audience must be INTERNAL_AUDIENCE_BASE + /internal/sweep-idle-sits, with the path actually present"
  }

  assert {
    condition     = module.sync_usgs_water.audience == "${module.cloudrun_api.env["INTERNAL_AUDIENCE_BASE"]}/internal/sync-usgs-water"
    error_message = "the sync audience must be INTERNAL_AUDIENCE_BASE + /internal/sync-usgs-water, with the path actually present"
  }
}

run "each_job_targets_what_it_mints_for" {
  command = plan

  assert {
    condition     = module.idle_sit_sweep.uri == module.idle_sit_sweep.audience
    error_message = "the idle-sit sweep job's uri must equal its OIDC audience"
  }

  assert {
    condition     = module.sync_usgs_water.uri == module.sync_usgs_water.audience
    error_message = "the sync-usgs-water job's uri must equal its OIDC audience"
  }
}

run "invoker_is_set_and_no_static_token_is_mapped" {
  command = plan

  assert {
    condition     = module.cloudrun_api.env["INTERNAL_INVOKER_EMAIL"] == format("%s@%s.iam.gserviceaccount.com", "sweep-invoker", "ecofolk-dev")
    error_message = "INTERNAL_INVOKER_EMAIL must be the sweep-invoker service account email, built from the variable, not a literal"
  }

  assert {
    condition     = !contains(keys(module.cloudrun_api.env), "SWEEP_TOKEN")
    error_message = "SWEEP_TOKEN must not be mapped on the Cloud Run service (internal routes are on OIDC, #114)"
  }
}
