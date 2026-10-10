# Same region pin as modules/project/variables.tf (ef#391): the validation refuses any other value, and
# scripts/check-region-pin.sh covers anything hardcoded around it.
variable "region" {
  type        = string
  default     = "northamerica-northeast1" # Montréal — do not change (ef#391)
  description = "Artifact Registry location. Must always be northamerica-northeast1 (Montréal), ef#391."

  validation {
    condition     = var.region == "northamerica-northeast1"
    error_message = "region must be \"northamerica-northeast1\" (Montréal) — this is a hard constraint, not a default to change. See ef#391."
  }
}

variable "project_id" {
  type        = string
  description = "GCP project id that owns the repository. No default: every caller states its own project."
}

variable "repository_id" {
  type        = string
  description = "Artifact Registry repository id (lowercase letters, digits and hyphens)."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", var.repository_id))
    error_message = "repository_id must start with a lowercase letter and contain only lowercase letters, digits and hyphens (max 63 chars)."
  }
}

variable "description" {
  type        = string
  default     = "EcoFolk container images"
  description = "Human-readable description shown on the repository."
}
