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
