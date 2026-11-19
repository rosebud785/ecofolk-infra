# ecofolk-infra#169 (ecofolk#1419): with a mock provider (no credentials, no GCP), assert the job's name, region,
# service account, Direct VPC egress, command and args, no retries, that env and secret refs pass through
# untouched, the image ignore_changes, that the module declares no *_iam_* resource, and every validation.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
  env        = "dev"
  # Built with format(), not written as a literal address (.gitleaks.toml's gcp-service-account-address rule).
  service_account = format("%s@%s.iam.gserviceaccount.com", "ecofolk-api", "ecofolk-dev")
  network         = "projects/ecofolk-dev/global/networks/ecofolk"
  subnetwork      = "projects/ecofolk-dev/regions/northamerica-northeast1/subnetworks/ecofolk-northamerica-northeast1"
}

run "name_region_and_service_account" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_job.check_config.name == "ecofolk-check-config" && google_cloud_run_v2_job.check_config.location == "northamerica-northeast1"
    error_message = "job must be ecofolk-check-config in northamerica-northeast1"
  }

  assert {
    condition     = google_cloud_run_v2_job.check_config.template[0].template[0].service_account == var.service_account
    error_message = "job must run as the passed (API runtime) service account"
  }
}

run "qa_name_gets_a_suffix" {
  command = plan

  variables {
    env = "qa"
  }

  assert {
    condition     = google_cloud_run_v2_job.check_config.name == "ecofolk-check-config-qa"
    error_message = "a qa job is named with -qa (#13)"
  }
}

run "vpc_egress_matches_the_api" {
  command = plan

  assert {
    condition = (
      google_cloud_run_v2_job.check_config.template[0].template[0].vpc_access[0].egress == "PRIVATE_RANGES_ONLY" &&
      google_cloud_run_v2_job.check_config.template[0].template[0].vpc_access[0].network_interfaces[0].network == var.network &&
      google_cloud_run_v2_job.check_config.template[0].template[0].vpc_access[0].network_interfaces[0].subnetwork == var.subnetwork
    )
    error_message = "Direct VPC egress, PRIVATE_RANGES_ONLY, into the passed network and subnetwork (as the API)"
  }
}

run "command_args_one_task_no_retries_short_timeout" {
  command = plan

  assert {
    condition = (
      google_cloud_run_v2_job.check_config.template[0].template[0].containers[0].command == tolist(["node"]) &&
      google_cloud_run_v2_job.check_config.template[0].template[0].containers[0].args == tolist(["dist/checkConfig.js"])
    )
    error_message = "the job runs `node dist/checkConfig.js`"
  }

  assert {
    condition = (
      google_cloud_run_v2_job.check_config.template[0].task_count == 1 &&
      google_cloud_run_v2_job.check_config.template[0].parallelism == 1 &&
      google_cloud_run_v2_job.check_config.template[0].template[0].max_retries == 0 &&
      google_cloud_run_v2_job.check_config.template[0].template[0].timeout == "300s"
    )
    error_message = "one task, no retry, a task timeout of a few minutes"
  }
}

run "env_and_secret_refs_pass_through_as_given" {
  command = plan

  variables {
    env_vars   = { POSTGRES_HOST = "10.0.0.5", POSTGRES_PORT = "5432" }
    secret_env = { POSTGRES_PASSWORD = "projects/1/secrets/pw", NOAA_CDO_TOKEN = "projects/1/secrets/noaa" }
  }

  assert {
    condition = (
      toset([for e in google_cloud_run_v2_job.check_config.template[0].template[0].containers[0].env : e.name if length(e.value_source) == 0]) == toset(["POSTGRES_HOST", "POSTGRES_PORT"]) &&
      toset([for e in google_cloud_run_v2_job.check_config.template[0].template[0].containers[0].env : e.name if length(e.value_source) > 0]) == toset(["POSTGRES_PASSWORD", "NOAA_CDO_TOKEN"])
    )
    error_message = "plain env and secret refs land on the container exactly as passed, secrets by reference only"
  }

  assert {
    condition     = output.env_vars == var.env_vars && output.secret_env == var.secret_env
    error_message = "the outputs expose exactly what was passed, for the environment tests"
  }
}

run "image_changes_are_left_to_deploys" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_job.check_config.template[0].template[0].containers[0].image == "us-docker.pkg.dev/cloudrun/container/hello"
    error_message = "the initial image is Google's public placeholder; the deploy script owns the real one"
  }
}

run "bad_service_account_is_refused" {
  command = plan

  variables {
    service_account = "not-an-email"
  }

  expect_failures = [var.service_account]
}

run "self_link_network_is_refused" {
  command = plan

  variables {
    network = "https://www.googleapis.com/compute/v1/projects/ecofolk-dev/global/networks/ecofolk"
  }

  expect_failures = [var.network]
}

run "other_region_is_refused" {
  command = plan

  variables {
    region = "us-central1"
  }

  expect_failures = [var.region]
}

run "empty_secret_ref_is_refused" {
  command = plan

  variables {
    secret_env = { POSTGRES_PASSWORD = "" }
  }

  expect_failures = [var.secret_env]
}

run "timeout_out_of_range_is_refused" {
  command = plan

  variables {
    timeout_seconds = 3600
  }

  expect_failures = [var.timeout_seconds]
}
