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
  default     = "ecofolk-check-config"
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
  description = "Email of the API's runtime service account: the job runs as the service does. Created locally, never here."

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
  default     = 300
  description = "Task timeout in seconds. The check connects twice and loads a config, so minutes is plenty; a longer run fails the execution and the deploy is refused."

  validation {
    condition     = var.timeout_seconds >= 60 && var.timeout_seconds <= 900
    error_message = "timeout_seconds must be between 60 and 900."
  }
}

# Terraform owns the command (as modules/migrate_job): static, so an apply never fights the deploy script, which
# sets the image only. The image's WORKDIR is /app/packages/api, so the arg is relative to it.
variable "command" {
  type        = list(string)
  default     = ["node"]
  description = "Container entrypoint. Terraform owns it; the deploy script updates the image only."
}

variable "args" {
  type        = list(string)
  default     = ["dist/checkConfig.js"]
  description = "Container args: the check-config entry (ecofolk#1419), relative to the image's WORKDIR. Terraform owns them; the deploy script updates the image only."
}

# The SAME refs the service maps: the caller passes one shared local to both. Never a value.
variable "secret_env" {
  type        = map(string)
  default     = {}
  description = "Env var name -> Secret Manager secret, mapped by secret_key_ref at version latest: the same map the API service gets. References only, never values."

  validation {
    condition     = alltrue([for v in values(var.secret_env) : length(v) > 0])
    error_message = "secret_env values must be non-empty secret references."
  }
}

# The SAME plain env the service gets (one shared local in the caller), or the check proves nothing.
variable "env_vars" {
  type        = map(string)
  default     = {}
  description = "Plain environment variables for the container: the same map the API service gets. NON-SECRET values only: this lands in state and in the public repo."
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
