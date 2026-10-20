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

# Dev only (#14): a *-prod project id (or its suffixed form) is refused, so no prod composition can
# instantiate the stop/start jobs.
variable "project_id" {
  type        = string
  description = "GCP project id of the dev project that owns the instance. Must not be a *-prod project."

  validation {
    condition     = !can(regex("-prod(-|$)", lower(var.project_id)))
    error_message = "project_id must not be a prod project: the off-hours stop/start is dev only (ecofolk-infra#14)."
  }
}

variable "instance_name" {
  type        = string
  description = "Name of the Cloud SQL instance to stop and start; pass module.cloudsql.instance_name."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,96}[a-z0-9])?$", var.instance_name))
    error_message = "instance_name must start with a lowercase letter and contain only lowercase letters, digits and hyphens (max 98 chars)."
  }
}

# The identity both jobs' OAuth tokens are minted for: ops-scheduler, the same account as #2's export.
# Created locally (L1(a), ef#885), never here.
variable "service_account_email" {
  type        = string
  description = "Email of the service account the stop and start jobs run as (ops-scheduler in the dev project). Created locally, never here."

  validation {
    condition     = can(regex("^[^@\\s]+@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", var.service_account_email))
    error_message = "service_account_email must be a service account email (<id>@<project>.iam.gserviceaccount.com)."
  }
}

variable "enable_off_hours" {
  type        = bool
  default     = true
  description = "Create the 22:15 CT stop and 04:45 CT start jobs. False creates neither, so the instance runs around the clock."
}

# #13: the env label and name suffix every module takes. This module is dev only, and qa shares dev's
# instance (#13), so this stop and start already covers it, so only "dev" is accepted: a qa root can't make a second copy.
variable "env" {
  type        = string
  description = "Environment. Dev only: must be \"dev\" (#13). Sets the `env` label and the (empty) name suffix."

  validation {
    condition     = var.env == "dev"
    error_message = "env must be \"dev\": this module is dev only, and qa shares dev's project (#13)."
  }
}
