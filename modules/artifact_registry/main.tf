# main.tf — Artifact Registry Docker repository for EcoFolk's container images (ecofolk-infra#4).
#
# Without cleanup, image storage grows forever against the credit, so the two cleanup policies below
# are part of the repository, not an afterthought:
#   - KEEP the 10 most recent versions (Artifact Registry's `most_recent_versions` condition), so a
#     recent image is never removed by the delete rule below;
#   - DELETE untagged images older than 7 days (604800s).
# `cleanup_policy_dry_run = false`: the policies actually delete, they don't just report.
#
# Location comes from var.region, which is validated to northamerica-northeast1 (ef#391); it is
# never hardcoded here.
#
# Needs artifactregistry.googleapis.com, which modules/project enables.
# LOCAL FOLLOW-UP: roles/artifactregistry.writer for the image-push identity, and
# roles/artifactregistry.reader for the Cloud Run service agent, on this repository. IAM is never
# written in this repo by a cloud session; a human-side session adds both bindings.
locals {
  keep_recent_count     = 10
  untagged_max_age_secs = 7 * 24 * 60 * 60
}

resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = var.description
  format        = "DOCKER"

  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-10-most-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = local.keep_recent_count
    }
  }

  cleanup_policies {
    id     = "delete-untagged-older-than-7d"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "${local.untagged_max_age_secs}s"
    }
  }
}
