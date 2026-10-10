# Plan-only tests against a mocked google provider: no credentials, no GCP calls (ecofolk-infra#4 AC).
mock_provider "google" {}

variables {
  project_id    = "ecofolk-dev"
  repository_id = "ecofolk-images"
}

run "docker_repo_region_pinned" {
  command = plan

  assert {
    condition     = google_artifact_registry_repository.docker.format == "DOCKER"
    error_message = "repository format must be DOCKER"
  }

  assert {
    condition     = google_artifact_registry_repository.docker.location == "northamerica-northeast1"
    error_message = "repository must be in northamerica-northeast1"
  }

  assert {
    condition     = google_artifact_registry_repository.docker.cleanup_policy_dry_run == false
    error_message = "cleanup_policy_dry_run must be false"
  }

  assert {
    condition     = length(google_artifact_registry_repository.docker.cleanup_policies) == 2
    error_message = "expected exactly two cleanup policies"
  }
}

run "keep_10_most_recent" {
  command = plan

  assert {
    condition = length([
      for p in google_artifact_registry_repository.docker.cleanup_policies : p
      if p.id == "keep-10-most-recent" && p.action == "KEEP"
      && length(p.most_recent_versions) == 1
      && one(p.most_recent_versions).keep_count == 10
    ]) == 1
    error_message = "expected a KEEP policy keeping the 10 most recent versions"
  }
}

run "delete_untagged_older_than_7_days" {
  command = plan

  assert {
    condition = length([
      for p in google_artifact_registry_repository.docker.cleanup_policies : p
      if p.id == "delete-untagged-older-than-7d" && p.action == "DELETE"
      && length(p.condition) == 1
      && one(p.condition).tag_state == "UNTAGGED"
      && one(p.condition).older_than == "604800s"
    ]) == 1
    error_message = "expected a DELETE policy for UNTAGGED images older than 604800s (7 days)"
  }
}

run "rejects_other_region" {
  command = plan

  variables {
    region = "us-east1"
  }

  expect_failures = [var.region]
}
