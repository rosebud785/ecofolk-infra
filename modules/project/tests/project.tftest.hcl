# Mock provider only: no credentials, no GCP.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
}

run "enables_the_network_apis" {
  command = plan

  # Issue #1: the VPC and Private Service Access need these two.
  assert {
    condition     = contains(keys(google_project_service.apis), "compute.googleapis.com")
    error_message = "compute.googleapis.com must be enabled"
  }

  assert {
    condition     = contains(keys(google_project_service.apis), "servicenetworking.googleapis.com")
    error_message = "servicenetworking.googleapis.com must be enabled"
  }
}

run "enables_artifact_registry_api" {
  command = plan

  assert {
    condition     = contains(keys(google_project_service.apis), "artifactregistry.googleapis.com")
    error_message = "artifactregistry.googleapis.com must be enabled (ecofolk-infra#4)"
  }

  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"].disable_on_destroy == false
    error_message = "APIs must not be disabled on destroy"
  }
}

# ecofolk-infra#20: modules/auth needs Identity Toolkit, and Firebase.
run "enables_the_auth_apis" {
  command = plan

  assert {
    condition     = contains(keys(google_project_service.apis), "identitytoolkit.googleapis.com")
    error_message = "identitytoolkit.googleapis.com must be enabled (ecofolk-infra#20)"
  }

  assert {
    condition     = contains(keys(google_project_service.apis), "firebase.googleapis.com")
    error_message = "firebase.googleapis.com must be enabled (ecofolk-infra#20)"
  }
}

# ecofolk-infra#21: modules/media_bucket needs Cloud Storage.
run "enables_the_storage_api" {
  command = plan

  assert {
    condition     = contains(keys(google_project_service.apis), "storage.googleapis.com")
    error_message = "storage.googleapis.com must be enabled (ecofolk-infra#21)"
  }
}

# ecofolk-infra#22: modules/web_hosting needs Firebase Hosting (and Firebase, asserted above).
run "enables_the_hosting_api" {
  command = plan

  assert {
    condition     = contains(keys(google_project_service.apis), "firebasehosting.googleapis.com")
    error_message = "firebasehosting.googleapis.com must be enabled (ecofolk-infra#22)"
  }
}

# ecofolk-infra#32: modules/secrets needs Secret Manager.
run "enables_the_secret_manager_api" {
  command = plan

  assert {
    condition     = contains(keys(google_project_service.apis), "secretmanager.googleapis.com")
    error_message = "secretmanager.googleapis.com must be enabled (ecofolk-infra#32)"
  }
}

run "region_defaults_to_the_pin" {
  command = plan

  assert {
    condition     = output.region == "northamerica-northeast1"
    error_message = "region must default to northamerica-northeast1"
  }
}

run "rejects_another_region" {
  command = plan

  variables {
    region = "northamerica-northeast2"
  }

  expect_failures = [var.region]
}

# ecofolk-infra#8: BUILD_PLAN §11.1's own list (Cloud Run, Cloud SQL, Cloud Build, Vertex AI, Firebase).
run "enables_the_build_plan_apis" {
  command = plan

  assert {
    condition = alltrue([
      for api in [
        "run.googleapis.com",
        "sqladmin.googleapis.com",
        "cloudbuild.googleapis.com",
        "aiplatform.googleapis.com",
        "firebase.googleapis.com",
      ] : contains(keys(google_project_service.apis), api)
    ])
    error_message = "every BUILD_PLAN §11.1 API must be enabled"
  }
}

run "every_api_is_on_the_given_project_and_kept_on_destroy" {
  command = plan

  assert {
    condition     = alltrue([for s in google_project_service.apis : s.project == "ecofolk-dev" && s.disable_on_destroy == false])
    error_message = "every API must be enabled on var.project_id and never disabled on destroy"
  }

  assert {
    condition     = output.project_id == "ecofolk-dev"
    error_message = "project_id output must echo var.project_id"
  }
}
