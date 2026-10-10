# Same region pin as modules/project/variables.tf (ef#391): the validation refuses any other value, and
# scripts/check-region-pin.sh covers anything hardcoded around it.
variable "region" {
  type        = string
  default     = "northamerica-northeast1" # Montréal — do not change (ef#391)
  description = "Cloud SQL region. Must always be northamerica-northeast1 (Montréal), ef#391."

  validation {
    condition     = var.region == "northamerica-northeast1"
    error_message = "region must be \"northamerica-northeast1\" (Montréal) — this is a hard constraint, not a default to change. See ef#391."
  }
}

variable "project_id" {
  type        = string
  description = "GCP project id that owns the instance. No default: every caller states its own project."
}

variable "private_network" {
  type        = string
  description = "Self-link of the VPC the instance takes its private IP in; pass module.network.network_self_link."
}

variable "instance_name" {
  type        = string
  default     = "ecofolk-pg"
  description = "Cloud SQL instance name (lowercase letters, digits and hyphens)."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,96}[a-z0-9])?$", var.instance_name))
    error_message = "instance_name must start with a lowercase letter and contain only lowercase letters, digits and hyphens (max 98 chars)."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Sets both Terraform's deletion_protection and the instance's settings.deletion_protection_enabled."
}

# The policy (policy/module_vars.rego, #39) accepts var.tier only while this default is a literal on the
# tier allowlist (policy/data.json) and every caller omits tier or passes a literal on it.
variable "tier" {
  type        = string
  default     = "db-f1-micro"
  description = "Machine tier. Must be on the policy allowlist (policy/data.json); callers pass a literal or omit it."
}
