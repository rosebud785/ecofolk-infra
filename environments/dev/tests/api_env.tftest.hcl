# ecofolk-infra#160 (Architect spec, ecofolk#1417 c6884039366): the dev API service's full runtime env. A
# production-mode boot (Cloud Run sets K_SERVICE) refuses a missing CONTACT_URL / NOMINATIM_BASE_URL and, worse,
# silently misbehaves on a missing FIREBASE_PROJECT_ID (every token 401s) or POSTGRES_PORT (the code default is
# 5440). So assert the EXACT key set: a missing or stray key fails here, and none of the dev-stack/emulator
# switches may appear.
#
# Mutation check (by hand): delete one env_vars line in main.tf, or add GCS_API_ENDPOINT; the key-set assert fails.
#
# Not run by CI (the tf-test job only tests modules/*). Run it locally:
#   terraform -chdir=environments/dev init -backend=false && terraform -chdir=environments/dev test
mock_provider "google" {}
mock_provider "google-beta" {}

override_resource {
  target = module.web_hosting.google_firebase_project.this
}

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

run "api_env_is_exactly_the_spec" {
  command = plan

  assert {
    condition = toset(keys(module.cloudrun_api.env_vars)) == toset([
      "INTERNAL_AUDIENCE_BASE",
      "INTERNAL_INVOKER_EMAIL",
      "CONTACT_URL",
      "NOMINATIM_BASE_URL",
      "FIREBASE_PROJECT_ID",
      "STORAGE_BACKEND",
      "GCS_BUCKET",
      "POSTGRES_HOST",
      "POSTGRES_PORT",
      "POSTGRES_USER",
      "POSTGRES_DB",
    ])
    error_message = "the dev API env key set must be exactly the Architect spec (ecofolk#1417 c6884039366): a missing key breaks boot, a stray one (an emulator or dev-stack switch) breaks production mode"
  }

  assert {
    condition     = length(setintersection(toset(keys(module.cloudrun_api.env_vars)), toset(["ECOFOLK_DEV_STACK", "FIREBASE_AUTH_EMULATOR_HOST", "GCS_API_ENDPOINT", "STORAGE_EMULATOR_HOST", "INTERNAL_DEV_CERT_PATH", "EXTERNAL_API_LIVE", "ALLOW_ANONYMOUS"]))) == 0
    error_message = "the must-stay-unset switches (emulators, dev stack, live-contract, anonymous) must not be set on the service"
  }

  assert {
    condition     = module.cloudrun_api.env_vars["POSTGRES_PORT"] == "5432" && module.cloudrun_api.env_vars["POSTGRES_USER"] == "ecofolk" && module.cloudrun_api.env_vars["STORAGE_BACKEND"] == "gcs"
    error_message = "POSTGRES_PORT must be explicit 5432 (code default 5440), POSTGRES_USER ecofolk, STORAGE_BACKEND gcs"
  }

  assert {
    condition     = module.cloudrun_api.env_vars["FIREBASE_PROJECT_ID"] == "ecofolk-dev" && startswith(module.cloudrun_api.env_vars["CONTACT_URL"], "https://")
    error_message = "FIREBASE_PROJECT_ID must be the project, CONTACT_URL an https URL"
  }
}
