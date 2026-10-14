# Issue #21 AC (Architect re-spec 2026-10-09, GCS): with a mock provider (no credentials, no GCP), assert
# the region, uniform access and public access prevention enforced, exactly one lifecycle rule (abort
# incomplete multipart uploads at age 1) and no Delete action, a 7-day soft delete, and no *_iam_*
# resource in the module.
mock_provider "google" {
  mock_resource "google_storage_bucket" {
    defaults = {
      url = "gs://ecofolk-dev-media"
    }
  }
}

variables {
  project_id = "ecofolk-dev"
  env        = "dev"
}

run "bucket_region_pinned_and_named" {
  command = plan

  assert {
    condition     = google_storage_bucket.media.location == "NORTHAMERICA-NORTHEAST1"
    error_message = "bucket must be in NORTHAMERICA-NORTHEAST1 (Montréal)"
  }

  assert {
    condition     = google_storage_bucket.media.name == "ecofolk-dev-media"
    error_message = "bucket must be named <project_id>-media"
  }

  assert {
    condition     = google_storage_bucket.media.project == "ecofolk-dev"
    error_message = "bucket must be created in var.project_id"
  }

  assert {
    condition     = google_storage_bucket.media.storage_class == "STANDARD"
    error_message = "storage_class must be STANDARD"
  }
}

run "bucket_is_private" {
  command = plan

  assert {
    condition     = google_storage_bucket.media.uniform_bucket_level_access == true
    error_message = "uniform_bucket_level_access must be true"
  }

  assert {
    condition     = google_storage_bucket.media.public_access_prevention == "enforced"
    error_message = "public_access_prevention must be enforced"
  }

  assert {
    condition     = length(google_storage_bucket.media.cors) == 0
    error_message = "no CORS: the browser never talks to the bucket"
  }

  assert {
    condition     = google_storage_bucket.media.force_destroy == false
    error_message = "force_destroy must be false"
  }
}

run "versioning_off" {
  command = plan

  assert {
    condition     = length(google_storage_bucket.media.versioning) == 1 && one(google_storage_bucket.media.versioning).enabled == false
    error_message = "versioning must be declared and disabled"
  }
}

run "only_lifecycle_rule_aborts_multipart_uploads_at_age_1" {
  command = plan

  assert {
    condition     = length(google_storage_bucket.media.lifecycle_rule) == 1
    error_message = "expected exactly one lifecycle rule"
  }

  assert {
    condition = length([
      for r in google_storage_bucket.media.lifecycle_rule : r
      if one(r.action).type == "AbortIncompleteMultipartUpload" && one(r.condition).age == 1
    ]) == 1
    error_message = "the lifecycle rule must be AbortIncompleteMultipartUpload at age 1"
  }

  assert {
    condition = alltrue([
      for r in google_storage_bucket.media.lifecycle_rule : alltrue([for a in r.action : a.type != "Delete"])
    ])
    error_message = "no lifecycle rule may Delete: the app owns retention (ecofolk#310)"
  }
}

run "soft_delete_is_7_days" {
  command = plan

  assert {
    condition     = length(google_storage_bucket.media.soft_delete_policy) == 1 && one(google_storage_bucket.media.soft_delete_policy).retention_duration_seconds == 604800
    error_message = "soft delete must be declared at 604800s (7 days)"
  }
}

run "labels_include_env" {
  command = plan

  assert {
    condition     = google_storage_bucket.media.labels["env"] == "dev"
    error_message = "labels must include env = var.env"
  }
}

run "module_declares_no_iam_or_key" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"google_[a-z_]*(_iam_[a-z_]*|_hmac_key)\"", file("${path.module}/${f}")))
    ])
    error_message = "the module must declare no *_iam_* resource and no HMAC key: bucket access is local follow-up L-RUN"
  }

  # Guard the guard: the scan above must actually see the module's files.
  assert {
    condition     = contains(fileset(path.module, "*.tf"), "main.tf")
    error_message = "the IAM scan found no main.tf, so it proves nothing"
  }
}

run "outputs" {
  command = apply

  assert {
    condition     = output.bucket_name == "ecofolk-dev-media"
    error_message = "bucket_name output must be <project_id>-media"
  }

  assert {
    condition     = output.bucket_url == "gs://ecofolk-dev-media"
    error_message = "bucket_url output must be the bucket's url"
  }
}

run "rejects_other_region" {
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
