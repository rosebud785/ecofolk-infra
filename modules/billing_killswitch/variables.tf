# Same region pin as modules/project/variables.tf (ef#391): the validation refuses any other value, and
# scripts/check-region-pin.sh covers anything hardcoded around it.
variable "region" {
  type        = string
  default     = "northamerica-northeast1" # Montréal — do not change (ef#391)
  description = "Region of the function, its trigger, the topic's message storage and the source bucket. Must always be northamerica-northeast1 (Montréal), ef#391."

  validation {
    condition     = var.region == "northamerica-northeast1"
    error_message = "region must be \"northamerica-northeast1\" (Montréal) — this is a hard constraint, not a default to change. See ef#391."
  }
}

variable "project_id" {
  type        = string
  description = "GCP project id that hosts the topic and function, and whose billing the function unlinks. No default: every caller states its own project."
}

# Dev only, never prod (#15). C7 (policy/billing_killswitch.rego) also refuses a *-prod id here and at
# every call site.
variable "project_allowlist" {
  type        = list(string)
  default     = ["ecofolk-dev"]
  description = "Project ids the function may unlink billing from. It does nothing for any other project. Never a *-prod id."

  validation {
    condition     = alltrue([for p in var.project_allowlist : !endswith(lower(p), "-prod")])
    error_message = "project_allowlist must never contain a *-prod project id: unlinking prod's billing takes the beta down (#15)."
  }

  validation {
    condition     = alltrue([for p in var.project_allowlist : can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", p))])
    error_message = "each project_allowlist entry must be a GCP project id (6-30 chars: lower-case letters, digits, hyphens)."
  }
}

# Names below are the Architect's defaults on #15 (2026-10-16): the local L-slot paste (ef#885) creates the
# identities and bindings under exactly these names. Never rename.
variable "service_account_id" {
  type        = string
  default     = "ecofolk-killswitch"
  description = "Account id (the part before @) of the function's runtime SA, also used by its trigger. Created locally (ef#885), not here."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_account_id))
    error_message = "service_account_id must be a service account id (6-30 chars: lower-case letters, digits, hyphens)."
  }
}

variable "topic_name" {
  type        = string
  default     = "ecofolk-dev-killswitch"
  description = "Pub/Sub topic the budget publishes to. The local budget script (ef#885) points the budget at this name."
}

variable "budget_display_name" {
  type        = string
  default     = "ecofolk-dev-killswitch"
  description = "The only budget whose messages the function acts on; every other budget (ecofolk-all included) is ignored."

  validation {
    condition     = length(var.budget_display_name) > 0
    error_message = "budget_display_name must not be empty."
  }
}

variable "unlink_threshold" {
  type        = number
  default     = 1.0
  description = "The function unlinks when costAmount >= budgetAmount x this. 1.0 = 100% of the budget's actual (gross) spend."

  validation {
    condition     = var.unlink_threshold > 0
    error_message = "unlink_threshold must be greater than 0."
  }
}

variable "function_name" {
  type        = string
  default     = "ecofolk-dev-killswitch"
  description = "Name of the Cloud Functions (2nd gen) function (and its Cloud Run service)."
}

# #13: the env label and name suffix every module takes. This module is dev only, and qa shares dev's
# instance and project (#13), so only "dev" is accepted: a qa root can't make a second copy.
variable "env" {
  type        = string
  description = "Environment. Dev only: must be \"dev\" (#13). Sets the `env` label and the (empty) name suffix."

  validation {
    condition     = var.env == "dev"
    error_message = "env must be \"dev\": this module is dev only, and qa shares dev's project (#13)."
  }
}
