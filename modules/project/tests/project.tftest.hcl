# Plan-only tests against a mocked google provider: no credentials, no GCP calls.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
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

run "region_pinned" {
  command = plan

  assert {
    condition     = output.region == "northamerica-northeast1"
    error_message = "region must be northamerica-northeast1"
  }
}
