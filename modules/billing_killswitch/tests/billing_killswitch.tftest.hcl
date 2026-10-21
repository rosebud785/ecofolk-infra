# Issue #15: with a mock provider (no credentials, no GCP), assert the topic and function names (the
# Architect's defaults, matching the local ef#885 paste), the region pin on every regional piece, the
# trigger wiring, the function's allowlist / budget name / threshold, scale-to-zero, the private source
# bucket, and that the module declares no IAM and no service account. archive is the real provider: it only
# zips function/ locally. The function's own logic is unit-tested in tests/test_main.py.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
  env        = "dev"
}

run "topic_has_the_architect_name_and_stays_in_montreal" {
  command = plan

  assert {
    condition     = google_pubsub_topic.budget.name == "ecofolk-dev-killswitch"
    error_message = "the topic must be ecofolk-dev-killswitch (Architect, #15)"
  }

  assert {
    condition     = google_pubsub_topic.budget.message_storage_policy[0].allowed_persistence_regions == tolist(["northamerica-northeast1"])
    error_message = "the topic must store messages in northamerica-northeast1 only"
  }
}

run "function_is_pinned_and_wired_to_the_topic" {
  command = apply

  assert {
    condition     = google_cloudfunctions2_function.killswitch.location == "northamerica-northeast1"
    error_message = "the function must run in northamerica-northeast1"
  }

  assert {
    condition     = google_cloudfunctions2_function.killswitch.event_trigger[0].trigger_region == "northamerica-northeast1"
    error_message = "the trigger must be in northamerica-northeast1"
  }

  assert {
    condition     = google_cloudfunctions2_function.killswitch.event_trigger[0].event_type == "google.cloud.pubsub.topic.v1.messagePublished"
    error_message = "the function must be triggered by Pub/Sub messagePublished"
  }

  assert {
    condition     = google_cloudfunctions2_function.killswitch.event_trigger[0].pubsub_topic == google_pubsub_topic.budget.id
    error_message = "the trigger must listen on the budget topic"
  }

  assert {
    condition     = output.topic_id == google_pubsub_topic.budget.id
    error_message = "topic_id must be the budget topic's id"
  }

  assert {
    condition     = output.function_name == "ecofolk-dev-killswitch"
    error_message = "function_name must be the function's name"
  }
}

# The address is assembled with format() so no literal SA address sits in this public repo (CONTRIBUTING).
run "runs_as_the_locally_created_killswitch_sa" {
  command = plan

  assert {
    condition     = google_cloudfunctions2_function.killswitch.service_config[0].service_account_email == format("%s@%s.iam.gserviceaccount.com", "ecofolk-killswitch", "ecofolk-dev")
    error_message = "the function must run as ecofolk-killswitch@<project> (Architect, #15)"
  }

  assert {
    condition     = google_cloudfunctions2_function.killswitch.event_trigger[0].service_account_email == format("%s@%s.iam.gserviceaccount.com", "ecofolk-killswitch", "ecofolk-dev")
    error_message = "the trigger must use ecofolk-killswitch@<project>"
  }

  assert {
    condition     = output.service_account_email == format("%s@%s.iam.gserviceaccount.com", "ecofolk-killswitch", "ecofolk-dev")
    error_message = "service_account_email must be ecofolk-killswitch@<project>"
  }
}

run "function_gets_allowlist_budget_name_and_threshold" {
  command = plan

  assert {
    condition = google_cloudfunctions2_function.killswitch.service_config[0].environment_variables == tomap({
      TARGET_PROJECT_ID   = "ecofolk-dev"
      UNLINK_ALLOWLIST    = "ecofolk-dev"
      BUDGET_DISPLAY_NAME = "ecofolk-dev-killswitch"
      UNLINK_THRESHOLD    = "1"
    })
    error_message = "the function must get project ecofolk-dev, allowlist [ecofolk-dev], budget ecofolk-dev-killswitch and threshold 1"
  }

  assert {
    condition     = google_cloudfunctions2_function.killswitch.build_config[0].entry_point == "on_budget_message"
    error_message = "the entry point must be on_budget_message (function/main.py)"
  }

  assert {
    condition     = startswith(google_cloudfunctions2_function.killswitch.build_config[0].runtime, "python")
    error_message = "the function must be Python"
  }
}

run "threshold_variable_reaches_the_function" {
  command = plan

  variables {
    unlink_threshold = 0.9
  }

  assert {
    condition     = google_cloudfunctions2_function.killswitch.service_config[0].environment_variables["UNLINK_THRESHOLD"] == "0.9"
    error_message = "unlink_threshold must be passed to the function"
  }
}

run "scales_to_zero_with_one_instance_max" {
  command = plan

  assert {
    condition     = google_cloudfunctions2_function.killswitch.service_config[0].min_instance_count == 0
    error_message = "the function must scale to zero"
  }

  assert {
    condition     = google_cloudfunctions2_function.killswitch.service_config[0].max_instance_count == 1
    error_message = "the function must be capped at one instance"
  }

  assert {
    condition     = google_cloudfunctions2_function.killswitch.service_config[0].ingress_settings == "ALLOW_INTERNAL_ONLY"
    error_message = "the function must not take public traffic"
  }
}

run "source_bucket_is_private_and_in_montreal" {
  command = plan

  assert {
    condition     = google_storage_bucket.source.location == "NORTHAMERICA-NORTHEAST1"
    error_message = "the source bucket must be in NORTHAMERICA-NORTHEAST1"
  }

  assert {
    condition     = google_storage_bucket.source.public_access_prevention == "enforced"
    error_message = "the source bucket must enforce public access prevention"
  }

  assert {
    condition     = google_storage_bucket.source.uniform_bucket_level_access == true
    error_message = "the source bucket must use uniform bucket-level access"
  }
}

run "enables_the_function_apis" {
  command = plan

  assert {
    condition = toset(keys(google_project_service.apis)) == toset([
      "cloudfunctions.googleapis.com",
      "eventarc.googleapis.com",
      "pubsub.googleapis.com",
      "cloudbilling.googleapis.com",
    ])
    error_message = "the module must enable Cloud Functions, Eventarc, Pub/Sub and Cloud Billing"
  }

  assert {
    condition     = alltrue([for s in google_project_service.apis : s.disable_on_destroy == false])
    error_message = "APIs must not be disabled on destroy"
  }
}

# The SA and every grant are local (ef#885); this module creates neither.
run "declares_no_iam_and_no_service_account" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"[a-z0-9_]*_iam_[a-z0-9_]*\"", file("${path.module}/${f}")))
    ])
    error_message = "the module must not declare any *_iam_* resource (IAM is local follow-up, ef#885)"
  }

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"google_service_account[a-z_]*\"", file("${path.module}/${f}")))
    ])
    error_message = "the module must not create a service account or key (created locally, ef#885)"
  }
}

run "rejects_a_prod_project_on_the_allowlist" {
  command = plan

  variables {
    project_allowlist = ["ecofolk-dev", "ecofolk-prod"]
  }

  expect_failures = [var.project_allowlist]
}

run "rejects_a_non_project_id_on_the_allowlist" {
  command = plan

  variables {
    project_allowlist = ["Ecofolk Dev"]
  }

  expect_failures = [var.project_allowlist]
}

run "rejects_another_region" {
  command = plan

  variables {
    region = "northamerica-northeast2"
  }

  expect_failures = [var.region]
}

run "rejects_a_zero_threshold" {
  command = plan

  variables {
    unlink_threshold = 0
  }

  expect_failures = [var.unlink_threshold]
}

run "rejects_a_bad_service_account_id" {
  command = plan

  variables {
    service_account_id = "Ecofolk_Killswitch"
  }

  expect_failures = [var.service_account_id]
}

# Issue #13: env. dev only: the names are unchanged, every label is env = dev, and qa and prod are refused.

run "env_dev_keeps_its_names_and_labels" {
  command = plan

  assert {
    condition     = google_pubsub_topic.budget.name == "ecofolk-dev-killswitch" && google_cloudfunctions2_function.killswitch.name == "ecofolk-dev-killswitch" && google_storage_bucket.source.name == "ecofolk-dev-killswitch-src"
    error_message = "dev must keep the topic, function and bucket names"
  }

  assert {
    condition     = google_pubsub_topic.budget.labels.env == "dev" && google_storage_bucket.source.labels.env == "dev" && google_cloudfunctions2_function.killswitch.labels.env == "dev"
    error_message = "every labelled resource must carry env = dev"
  }

  assert {
    condition = sort(output.resource_names) == sort([
      "google_project_service/cloudfunctions.googleapis.com",
      "google_project_service/eventarc.googleapis.com",
      "google_project_service/pubsub.googleapis.com",
      "google_project_service/cloudbilling.googleapis.com",
      "google_pubsub_topic/ecofolk-dev-killswitch",
      "google_storage_bucket/ecofolk-dev-killswitch-src",
      "google_cloudfunctions2_function/ecofolk-dev-killswitch",
    ])
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

run "env_refuses_qa" {
  command = plan

  variables {
    env = "qa"
  }

  expect_failures = [var.env]
}

run "env_refuses_prod" {
  command = plan

  variables {
    env = "prod"
  }

  expect_failures = [var.env]
}
