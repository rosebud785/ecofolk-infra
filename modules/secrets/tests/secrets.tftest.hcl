# Issue #32 AC: with a mock provider (no credentials, no GCP), assert four secrets with exactly the
# Architect's names, each with one user-managed replica in Montréal and the env label, the id map output,
# and that the module declares no secret version (no value) and no IAM.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
  env        = "dev"
}

run "creates_exactly_the_four_named_secrets" {
  command = plan

  assert {
    condition     = length(google_secret_manager_secret.secret) == 4
    error_message = "there must be exactly four secrets"
  }

  # The exact names are a contract with the human-run access script: never renamed.
  assert {
    condition = toset(keys(google_secret_manager_secret.secret)) == toset([
      "POSTGRES_PASSWORD",
      "POSTGRES_INGEST_PASSWORD",
      "SWEEP_TOKEN",
      "NOAA_CDO_TOKEN",
    ])
    error_message = "the secrets must be exactly POSTGRES_PASSWORD, POSTGRES_INGEST_PASSWORD, SWEEP_TOKEN and NOAA_CDO_TOKEN"
  }

  assert {
    condition     = alltrue([for k, s in google_secret_manager_secret.secret : s.secret_id == k && s.project == "ecofolk-dev"])
    error_message = "each secret's secret_id must be its name, on var.project_id"
  }
}

run "replication_is_user_managed_in_montreal_only" {
  command = plan

  assert {
    condition = alltrue([
      for s in google_secret_manager_secret.secret :
      length(s.replication) == 1
      && length(s.replication[0].auto) == 0
      && length(s.replication[0].user_managed) == 1
      && length(s.replication[0].user_managed[0].replicas) == 1
      && s.replication[0].user_managed[0].replicas[0].location == "northamerica-northeast1"
    ])
    error_message = "every secret must have user-managed replication with exactly one replica, in northamerica-northeast1 (no auto replication)"
  }
}

run "labels_carry_env" {
  command = plan

  assert {
    condition     = alltrue([for s in google_secret_manager_secret.secret : s.labels["env"] == "dev"])
    error_message = "every secret must carry the env label"
  }
}

# Containers only. A version is a value; the module source must declare none (C7 refuses one too).
run "declares_no_version_and_no_iam" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"google_secret_manager_secret_version\"", file("${path.module}/${f}")))
    ])
    error_message = "the module must not declare google_secret_manager_secret_version (no values in this repo)"
  }

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"[a-z0-9_]*_iam_[a-z0-9_]*\"", file("${path.module}/${f}")))
    ])
    error_message = "the module must not declare any *_iam_* resource (accessor IAM is local follow-up, ecofolk#890)"
  }

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") : alltrue([
        for m in regexall("resource\\s+\"([a-z0-9_]+)\"", file("${path.module}/${f}")) :
        m[0] == "google_secret_manager_secret"
      ])
    ])
    error_message = "google_secret_manager_secret must be the only resource type in the module"
  }
}

run "outputs_map_name_to_id" {
  command = apply

  assert {
    condition     = toset(keys(output.secret_ids)) == toset(keys(google_secret_manager_secret.secret))
    error_message = "secret_ids must have one entry per secret name"
  }

  assert {
    condition     = alltrue([for k, id in output.secret_ids : id == google_secret_manager_secret.secret[k].id])
    error_message = "secret_ids must map each name to its secret's id"
  }
}

run "rejects_another_region" {
  command = plan

  variables {
    region = "northamerica-northeast2"
  }

  expect_failures = [var.region]
}

run "rejects_unknown_env" {
  command = plan

  variables {
    env = "staging"
  }

  expect_failures = [var.env]
}

run "rejects_a_non_env_var_name" {
  command = plan

  variables {
    secret_names = ["postgres-password"]
  }

  expect_failures = [var.secret_names]
}

run "rejects_a_repeated_name" {
  command = plan

  variables {
    secret_names = ["SWEEP_TOKEN", "SWEEP_TOKEN"]
  }

  expect_failures = [var.secret_names]
}
