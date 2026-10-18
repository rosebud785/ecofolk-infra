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

# The API's base URL; pass module.cloudrun_api.uri. The job appends /internal/sweep-idle-sits.
variable "api_url" {
  type        = string
  description = "Base URL of the API (https://<host>, no path, no trailing slash); pass module.cloudrun_api.uri."

  validation {
    condition     = can(regex("^https://[^/\\s]+$", var.api_url))
    error_message = "api_url must be https://<host> with no path and no trailing slash."
  }
}

# Architect amendment on #17 (2026-10-16): every 2 hours by default, under the 3h idle threshold.
# environments/dev passes 0 5-21/2 * * * so no sweep runs while dev Cloud SQL is stopped (#14).
variable "sweep_schedule" {
  type        = string
  default     = "0 */2 * * *"
  description = "Cron schedule (5 fields, America/Chicago) for the idle-sit sweep."

  validation {
    condition     = can(regex("^\\S+( \\S+){4}$", var.sweep_schedule))
    error_message = "sweep_schedule must be a 5-field cron expression separated by single spaces."
  }
}
