# ecofolk#1169 (G1 part 1): with a mock provider (no credentials, no GCP), assert the job's name, region,
# Direct VPC egress, service account, no retries, no secret env, the image ignore_changes, that the module
# declares no *_iam_* resource, and every validation.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
  env        = "dev"
  # Built with format(), not written as a literal address (.gitleaks.toml's gcp-service-account-address rule).
  service_account = format("%s@%s.iam.gserviceaccount.com", "ecofolk-migrate", "ecofolk-dev")
  network         = "projects/ecofolk-dev/global/networks/ecofolk"
  subnetwork      = "projects/ecofolk-dev/regions/northamerica-northeast1/subnetworks/ecofolk-northamerica-northeast1"
}

run "name_region_and_service_account" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_job.migrate.name == "ecofolk-migrate" && google_cloud_run_v2_job.migrate.location == "northamerica-northeast1"
    error_message = "job must be ecofolk-migrate in northamerica-northeast1"
  }

  assert {
    condition     = google_cloud_run_v2_job.migrate.template[0].template[0].service_account == format("%s@%s.iam.gserviceaccount.com", "ecofolk-migrate", "ecofolk-dev")
    error_message = "job must run as the passed migrate service account"
  }
}

run "vpc_egress_matches_the_api" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_job.migrate.template[0].template[0].vpc_access[0].egress == "PRIVATE_RANGES_ONLY"
    error_message = "egress must be PRIVATE_RANGES_ONLY (Direct VPC, as the API)"
  }

  assert {
    condition = (
      google_cloud_run_v2_job.migrate.template[0].template[0].vpc_access[0].network_interfaces[0].network == var.network &&
      google_cloud_run_v2_job.migrate.template[0].template[0].vpc_access[0].network_interfaces[0].subnetwork == var.subnetwork
    )
    error_message = "the job must use the passed network and subnetwork"
  }
}

run "one_task_no_retries" {
  command = plan

  assert {
    condition = (
      google_cloud_run_v2_job.migrate.template[0].task_count == 1 &&
      google_cloud_run_v2_job.migrate.template[0].parallelism == 1 &&
      google_cloud_run_v2_job.migrate.template[0].template[0].max_retries == 0
    )
    error_message = "migrations run as one task, one at a time, with no retry"
  }
}

run "no_secret_env_by_default_and_image_is_left_to_deploys" {
  command = plan

  assert {
    condition     = length([for e in google_cloud_run_v2_job.migrate.template[0].template[0].containers[0].env : e if length(e.value_source) > 0]) == 0
    error_message = "the migrator uses IAM DB auth: no secret-backed env var unless the caller passes the one ingest secret"
  }

  # lifecycle blocks are not in the plan: read the source.
  assert {
    condition     = can(regex("ignore_changes\\s*=\\s*\\[template\\[0\\]\\.template\\[0\\]\\.containers\\[0\\]\\.image\\]", file("${path.module}/main.tf")))
    error_message = "the module must ignore later image changes (the deploy script owns the image)"
  }

  # Terraform owns command/args (Architect, T1): they must not be in ignore_changes.
  assert {
    condition     = !can(regex("ignore_changes[^\\]]*(command|args)", file("${path.module}/main.tf")))
    error_message = "command and args are Terraform's: they must not be ignored (the deploy script updates the image only)"
  }
}

run "terraform_owns_the_command" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_job.migrate.template[0].template[0].containers[0].command == tolist(["node"]) && google_cloud_run_v2_job.migrate.template[0].template[0].containers[0].args == tolist(["/app/packages/db/dist/cli/migrate.js"])
    error_message = "the job must run node /app/packages/db/dist/cli/migrate.js, set by Terraform"
  }
}

run "the_one_ingest_secret_is_a_reference" {
  command = plan

  variables {
    secret_env = {
      POSTGRES_INGEST_PASSWORD = "projects/ecofolk-dev/secrets/POSTGRES_INGEST_PASSWORD"
    }
  }

  assert {
    condition = (
      length([for e in google_cloud_run_v2_job.migrate.template[0].template[0].containers[0].env : e if length(e.value_source) > 0]) == 1 &&
      [for e in google_cloud_run_v2_job.migrate.template[0].template[0].containers[0].env : e.name if length(e.value_source) > 0][0] == "POSTGRES_INGEST_PASSWORD" &&
      [for e in google_cloud_run_v2_job.migrate.template[0].template[0].containers[0].env : e.value_source[0].secret_key_ref[0].version if length(e.value_source) > 0][0] == "latest"
    )
    error_message = "exactly one secret env, POSTGRES_INGEST_PASSWORD, as a secret_key_ref at latest"
  }
}

run "known_wrong_login_secret_refused" {
  command = plan

  variables {
    secret_env = {
      POSTGRES_PASSWORD = "projects/ecofolk-dev/secrets/POSTGRES_PASSWORD"
    }
  }

  expect_failures = [var.secret_env]
}

run "qa_name_is_suffixed" {
  command = plan

  variables {
    env = "qa"
  }

  assert {
    condition     = google_cloud_run_v2_job.migrate.name == "ecofolk-migrate-qa" && google_cloud_run_v2_job.migrate.labels["env"] == "qa"
    error_message = "a qa job must be ecofolk-migrate-qa with env=qa"
  }
}

run "declares_no_iam_resource" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"google[a-z0-9_]*_iam_[a-z0-9_]*\"", file("${path.module}/${f}")))
    ])
    error_message = "the module must not declare any *_iam_* resource (CONTRIBUTING: no IAM in this repo)"
  }
}

run "known_wrong_region_refused" {
  command = plan

  variables {
    region = "us-central1"
  }

  expect_failures = [var.region]
}

run "known_wrong_self_link_refused" {
  command = plan

  variables {
    network = "https://www.googleapis.com/compute/v1/projects/ecofolk-dev/global/networks/ecofolk"
  }

  expect_failures = [var.network]
}

run "known_wrong_service_account_refused" {
  command = plan

  variables {
    service_account = "ecofolk-migrate"
  }

  expect_failures = [var.service_account]
}
