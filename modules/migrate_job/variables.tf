# Same region pin as modules/project/variables.tf (ef#391): the validation refuses any other value, and
# scripts/check-region-pin.sh covers anything hardcoded around it.
variable "region" {
  type        = string
  default     = "northamerica-northeast1" # Montréal — do not change (ef#391)
  description = "Cloud Run region. Must always be northamerica-northeast1 (Montréal), ef#391; pass module.project.region."

  validation {
    condition     = var.region == "northamerica-northeast1"
    error_message = "region must be \"northamerica-northeast1\" (Montréal) — this is a hard constraint, not a default to change. See ef#391."
  }
}

variable "project_id" {
  type        = string
  description = "GCP project id that owns the job. No default: every caller states its own project."
}

variable "name" {
  type        = string
  default     = "ecofolk-migrate"
  description = "Cloud Run job name (lowercase letters, digits and hyphens). A qa job gets -qa appended (#13)."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,44}[a-z0-9])?$", var.name))
    error_message = "name must start with a lowercase letter and contain only lowercase letters, digits and hyphens (max 46 chars, so the -qa suffix still fits)."
  }
}

# Only the initial image: the deploy script updates the job to the pushed digest and the module ignores changes to it.
variable "image" {
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
  description = "Container image for the first execution. Defaults to Google's public placeholder; the deploy script owns the image."
}

variable "service_account" {
  type        = string
  description = "Email of the keyless migrate service account the job runs as. Created locally, never here."

  validation {
    condition     = can(regex("^[^@\\s]+@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", var.service_account))
    error_message = "service_account must be a service account email (<id>@<project>.iam.gserviceaccount.com)."
  }
}

# Relative resource names (.id), not self-links, as for modules/cloudrun_api (ecofolk-infra#45).
variable "network" {
  type        = string
  description = "VPC for Direct VPC egress, as its relative resource name (.id), not self-link; pass module.network.network_id."

  validation {
    condition     = can(regex("^projects/[^/]+/[g]lobal/networks/[^/]+$", var.network))
    error_message = "network must be the VPC's relative resource name (.id, projects/<project>/<scope>/networks/<name>), not an https self-link (ecofolk-infra#45)."
  }
}

variable "subnetwork" {
  type        = string
  description = "Subnet for Direct VPC egress, as its relative resource name (.id), not self-link; pass module.network.subnet_id."

  validation {
    condition     = can(regex("^projects/[^/]+/regions/[^/]+/subnetworks/[^/]+$", var.subnetwork))
    error_message = "subnetwork must be the subnet's relative resource name (.id, projects/<project>/regions/<region>/subnetworks/<name>), not an https self-link (ecofolk-infra#45)."
  }
}

variable "timeout_seconds" {
  type        = number
  default     = 600
  description = "Task timeout in seconds. A migration that runs longer fails the execution, and the deploy is refused."

  validation {
    condition     = var.timeout_seconds >= 60 && var.timeout_seconds <= 3600
    error_message = "timeout_seconds must be between 60 and 3600."
  }
}

# Non-secret values only: the migrator uses IAM DB auth, so there is no password to map.
variable "env_vars" {
  type        = map(string)
  default     = {}
  description = "Plain environment variables for the container (DB host, name, IAM user). NON-SECRET values only: this lands in state and in the public repo."
}

# #13: dev, qa or prod. Labels the job; qa also suffixes its name with -qa.
variable "env" {
  type        = string
  description = "Environment: dev, qa or prod. Sets the `env` label; qa (a namespace inside ecofolk-dev, #13) also suffixes the job name with -qa."

  validation {
    condition     = contains(["dev", "qa", "prod"], var.env)
    error_message = "env must be \"dev\", \"qa\" or \"prod\"."
  }
}
