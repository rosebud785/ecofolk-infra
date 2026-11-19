# ecofolk-infra#169 (ecofolk#1419): the pre-deploy check job proves the service would boot only if it runs with
# EXACTLY what the service runs with. So assert, on the composed dev plan, that the job's plain env, secret refs and
# service account equal the API service's. Both come from one shared local (local.api_env_vars, local.api_secret_env,
# local.api_service_account_email), so the known-wrong is a variable added to ONE of them.
#
# Mutation check (by hand): in environments/dev/main.tf give module.check_config_job a copy of the env map with one
# key more or fewer (or add a key to the service's `env_vars` only); the first assert fails.
#
# Run by CI (the tf-test job loops over environments/*). To run it locally:
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

run "check_config_job_matches_the_service_exactly" {
  command = plan

  assert {
    condition     = toset(keys(module.check_config_job.env_vars)) == toset(keys(module.cloudrun_api.env_vars))
    error_message = "the check-config job's plain env key set must equal the API service's exactly, or the check proves nothing"
  }

  # Some values (the hosting URL, the bucket) are unknown until apply, so compare the ones a plan knows.
  assert {
    condition = alltrue([
      for k in ["POSTGRES_PORT", "POSTGRES_USER", "STORAGE_BACKEND", "FIREBASE_PROJECT_ID", "NOMINATIM_BASE_URL"] :
      module.check_config_job.env_vars[k] == module.cloudrun_api.env_vars[k]
    ])
    error_message = "the check-config job's plain env VALUES must equal the API service's (the plan-known ones are checked here)"
  }

  assert {
    condition     = toset(keys(module.check_config_job.secret_env)) == toset(keys(module.cloudrun_api.secret_env))
    error_message = "the check-config job's secret ref names must equal the API service's exactly"
  }

  assert {
    condition     = module.check_config_job.service_account == module.cloudrun_api.service_account
    error_message = "the check-config job must run as the API's runtime service account (no extra identity, no extra IAM)"
  }

  assert {
    condition     = length(module.check_config_job.secret_env) > 0 && length(module.check_config_job.env_vars) > 0
    error_message = "guard: an empty-equals-empty comparison would pass vacuously; the dev service has env and secrets"
  }
}

run "job_is_named_for_the_deploy_script" {
  command = plan

  assert {
    condition     = module.check_config_job.name == "ecofolk-check-config"
    error_message = "scripts/deploy/deploy-dev.sh (ecofolk) updates and executes the job named ecofolk-check-config (ECOFOLK_CHECK_CONFIG_JOB default)"
  }

  assert {
    condition     = contains(output.resource_names, "google_cloud_run_v2_job/ecofolk-check-config")
    error_message = "the job must be in the dev composition's resource_names (#13's dev/qa collision test)"
  }
}
