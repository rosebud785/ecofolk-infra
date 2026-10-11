# Pinned so `terraform validate` in CI is reproducible without ever needing
# `terraform init` to resolve a version range against the provider registry
# in a way that could drift between runs.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}
