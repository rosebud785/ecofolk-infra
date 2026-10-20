# The same project as environments/dev (#13: a namespace inside ecofolk-dev, not a third project), from the
# same §5 bootstrap output (repo variable GCP_PROJECT_ID). No default, so a run that forgets it fails
# instead of guessing.
variable "project_id" {
  type        = string
  description = "GCP project id of the dev project (ecofolk-dev, or its suffixed form) that the QA namespace lives in. Same value as environments/dev."
}

# This root calls no modules/project (dev's root owns the project's API enables, and a second owner would
# fight over them), so the pin is restated here with the same validation, for the subnet lookup and the
# Cloud Run service. scripts/check-region-pin.sh covers it like every other *.tf.
variable "region" {
  type        = string
  default     = "northamerica-northeast1" # Montréal — do not change (ef#391)
  description = "GCP region of dev's subnet and of the QA Cloud Run service. Must always be northamerica-northeast1 (Montréal), ef#391."

  validation {
    condition     = var.region == "northamerica-northeast1"
    error_message = "region must be \"northamerica-northeast1\" (Montréal) — this is a hard constraint, not a default to change. See ef#391."
  }
}

# #13: no new IAM. The QA service runs as dev's existing runtime SA (L-RUN), which tf-apply can already
# actAs, so nothing new is created or bound. Same default as environments/dev.
variable "api_service_account_id" {
  type        = string
  default     = "ecofolk-api"
  description = "Account id (the part before @) of the runtime service account the QA Cloud Run service runs as: dev's existing API runtime SA."
}

# Names of the dev resources QA reuses (#13). They must match what environments/dev creates: modules/network
# and modules/cloudsql's defaults, which dev doesn't override.
variable "dev_network_name" {
  type        = string
  default     = "ecofolk"
  description = "Name of dev's VPC (modules/network's default). The subnet is <name>-<region>."
}

variable "dev_sql_instance_name" {
  type        = string
  default     = "ecofolk-pg"
  description = "Name of dev's Cloud SQL instance (modules/cloudsql's default). QA gets its own database on it, never its own instance."
}
