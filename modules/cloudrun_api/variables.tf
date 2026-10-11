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
  description = "GCP project id that owns the service. No default: every caller states its own project."
}

variable "name" {
  type        = string
  default     = "ecofolk-api"
  description = "Cloud Run service name (lowercase letters, digits and hyphens)."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,47}[a-z0-9])?$", var.name))
    error_message = "name must start with a lowercase letter and contain only lowercase letters, digits and hyphens (max 49 chars)."
  }
}

# Only the initial image: deploys (ef#408) set the real one and the module ignores changes to it.
variable "image" {
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
  description = "Container image for the first revision. Defaults to Google's public placeholder; later deploys own the image."
}

# The policy (policy/module_vars.rego, #39) accepts var.max_instance_count only while this default is a
# literal within the cap (3 outside prod) and every caller omits it or passes a literal within its cap.
variable "max_instance_count" {
  type        = number
  default     = 3
  description = "Upper bound on instances. At most 3 (C7); callers pass a literal or omit it."

  validation {
    condition     = var.max_instance_count >= 1 && var.max_instance_count <= 3
    error_message = "max_instance_count must be between 1 and 3 (C7's dev cap)."
  }
}

variable "service_account" {
  type        = string
  description = "Email of the runtime service account the service runs as. Created locally (L-RUN), never here."

  validation {
    condition     = can(regex("^[^@\\s]+@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", var.service_account))
    error_message = "service_account must be a service account email (<id>@<project>.iam.gserviceaccount.com)."
  }
}

variable "network" {
  type        = string
  description = "Self-link of the VPC for Direct VPC egress; pass module.network.network_self_link."
}

variable "subnetwork" {
  type        = string
  description = "Self-link of the subnet for Direct VPC egress; pass module.network.subnet_self_link."
}

# Non-secret values only. Secrets come later as secret_key_ref to Secret Manager secret names (ef#399).
variable "env" {
  type        = map(string)
  default     = {}
  description = "Plain environment variables for the container. NON-SECRET values only: this lands in state and in the public repo."
}
