terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    # Zips function/ for the Cloud Functions source upload. Local only, no cloud calls.
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}
