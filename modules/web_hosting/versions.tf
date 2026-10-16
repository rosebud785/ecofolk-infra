# Pinned so `terraform validate` in CI is reproducible without ever needing
# `terraform init` to resolve a version range against the provider registry
# in a way that could drift between runs. google-beta is the spec's provider for
# the Firebase resources (ecofolk-infra#22), on the same major as `google`.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}
