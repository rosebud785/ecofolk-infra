# Same region pin as modules/project/variables.tf (ef#391): the validation refuses any other value, and
# scripts/check-region-pin.sh covers anything hardcoded around it.
variable "region" {
  type        = string
  default     = "northamerica-northeast1" # Montréal — do not change (ef#391)
  description = "Cloud Scheduler region. Must always be northamerica-northeast1 (Montréal), ef#391."

  validation {
    condition     = var.region == "northamerica-northeast1"
    error_message = "region must be \"northamerica-northeast1\" (Montréal) — this is a hard constraint, not a default to change. See ef#391."
  }
}

variable "project_id" {
  type        = string
  description = "GCP project id that owns the Scheduler job."
}

# The API's base URL; pass module.cloudrun_api.uri. The job appends /internal/sync-usgs-water.
variable "api_url" {
  type        = string
  description = "Base URL of the API (https://<host>, no path, no trailing slash); pass module.cloudrun_api.uri."

  validation {
    condition     = can(regex("^https://[^/\\s]+$", var.api_url))
    error_message = "api_url must be https://<host> with no path and no trailing slash."
  }
}

# The service account the job's OIDC ID token is minted for: the EXISTING sweep invoker (#17), created
# locally with no roles; never created here (Architect's cloud spec on #98). The API checks the token's
# email against it (ecofolk#1092).
variable "invoker_sa_email" {
  type        = string
  description = "Email of the existing sweep invoker service account (<id>@<project>.iam.gserviceaccount.com)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]@[a-z0-9][a-z0-9.:-]*[a-z0-9]\\.iam\\.gserviceaccount\\.com$", var.invoker_sa_email))
    error_message = "invoker_sa_email must be a user-managed service account address ending in .iam.gserviceaccount.com."
  }
}

# #13: dev, qa or prod. It is each resource's `env` label (where the type takes labels) and it suffixes
# each resource name: dev and prod each own a project, so their names stay as they are; qa is a namespace
# inside ecofolk-dev, so its names end in -qa and can't collide with dev's.
variable "env" {
  type        = string
  description = "Environment: dev, qa or prod. Sets the `env` label; qa (a namespace inside ecofolk-dev, #13) also suffixes each resource name with -qa."

  validation {
    condition     = contains(["dev", "qa", "prod"], var.env)
    error_message = "env must be \"dev\", \"qa\" or \"prod\"."
  }
}
