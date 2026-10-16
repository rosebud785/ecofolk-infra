terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.7"
    }
    # Firebase project + Hosting site (modules/web_hosting, ecofolk-infra#22).
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.7"
    }
  }
}
