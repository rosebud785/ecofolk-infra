# variables.tf — the single source of truth for the Montréal region pin (ef#391).
#
# Andy's hydro-power constraint is HARD: every GCP resource this project ever
# creates must run in `northamerica-northeast1` (Montréal). This module is the
# ONE place that constant is spelled out — every environment (dev, prod) gets
# it by simply not overriding `region`, so there is nothing to keep in sync.
#
# The `validation` block is enforcement, not documentation: `terraform
# validate` (and `plan`/`apply`, once those exist) REFUSES to proceed if any
# caller ever does pass a different region. Andy, on why this matters landing
# before any resource exists: "enforcement before provisioning is the only
# cheap time to do this — after resources exist, a region violation costs a
# migration instead of a grep."
#
# This validation block only catches a WRONG VALUE PASSED TO THIS VARIABLE. It
# does not catch a region hardcoded directly into some other resource's
# arguments, bypassing this variable entirely — that is what
# scripts/check-region-pin.sh's CI grep is for (ef#391's second,
# independent layer). Keep both; each catches what the other cannot.
variable "region" {
  type        = string
  default     = "northamerica-northeast1" # Montréal — do not change (ef#391)
  description = "GCP region. Must always be northamerica-northeast1 (Montréal, hydro-powered) — Andy's hard constraint, ef#391. Do not override this per-environment."

  validation {
    condition     = var.region == "northamerica-northeast1"
    error_message = "region must be \"northamerica-northeast1\" (Montréal) — this is a hard constraint, not a default to change. See ef#391."
  }
}

variable "project_id" {
  type        = string
  description = "GCP project id — \"ecofolk-dev\" or \"ecofolk-prod\" (BUILD_PLAN.md §11.1). No default: every environment must state its own project explicitly."
}

# BUILD_PLAN.md §11.1: "enable APIs (Cloud Run, Cloud SQL, Cloud Build, Vertex
# AI, Firebase)". Declaring the enable-service resources is safe scaffolding —
# `terraform validate` never contacts GCP, so this costs nothing and commits
# to nothing until a real `apply` runs against a project that exists (ef#390's
# AC is explicitly validate-only; `plan`/`apply` need credentials that do not
# exist yet).
variable "enabled_apis" {
  type = list(string)
  default = [
    "run.googleapis.com",        # Cloud Run
    "sqladmin.googleapis.com",   # Cloud SQL
    "cloudbuild.googleapis.com", # Cloud Build
    "aiplatform.googleapis.com", # Vertex AI
    "firebase.googleapis.com",   # Firebase
  ]
  description = "GCP APIs to enable on the project (BUILD_PLAN.md §11.1)."
}
