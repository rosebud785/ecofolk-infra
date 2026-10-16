# Same region pin as modules/project/variables.tf (ef#391): the validation refuses any other value, and
# scripts/check-region-pin.sh covers anything hardcoded around it.
variable "region" {
  type        = string
  default     = "northamerica-northeast1" # Montréal — do not change (ef#391)
  description = "Location of each secret's single user-managed replica. Must always be northamerica-northeast1 (Montréal), ef#391."

  validation {
    condition     = var.region == "northamerica-northeast1"
    error_message = "region must be \"northamerica-northeast1\" (Montréal) — this is a hard constraint, not a default to change. See ef#391."
  }
}

variable "project_id" {
  type        = string
  description = "GCP project id that owns the secrets. No default: every caller states its own project."
}

variable "env" {
  type        = string
  description = "Environment name, set as each secret's `env` label."

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be \"dev\" or \"prod\"."
  }
}

# Architect ruling on ecofolk#399 (ecofolk-infra#32). These exact names are a contract with the human-run
# access script and with the API's env var names: never rename. The R2 keys are gone under GCS/ADC (#926).
variable "secret_names" {
  type = list(string)
  default = [
    "POSTGRES_PASSWORD",
    "POSTGRES_INGEST_PASSWORD",
    "SWEEP_TOKEN",
    "NOAA_CDO_TOKEN",
  ]
  description = "Secret Manager secret ids to create as empty containers. Each is also the env var name the API reads it as."

  validation {
    condition     = alltrue([for n in var.secret_names : can(regex("^[A-Z][A-Z0-9_]{0,254}$", n))])
    error_message = "each secret name must be an env-var-style id: an upper-case letter, then upper-case letters, digits or underscores (max 255 chars)."
  }

  validation {
    condition     = length(distinct(var.secret_names)) == length(var.secret_names)
    error_message = "secret_names must not repeat a name."
  }
}
