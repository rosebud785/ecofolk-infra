# The GCP project id comes from the §5 bootstrap output (repo variable GCP_PROJECT_ID, fed to Terraform
# as TF_VAR_project_id by infra.yml), not from a literal in source: the id may carry a suffix if
# "ecofolk-dev" was taken. No default, so a run that forgets it fails instead of guessing.
variable "project_id" {
  type        = string
  description = "GCP project id of the dev project (ecofolk-dev, or its suffixed form). Set from repo variable GCP_PROJECT_ID."
}

# The runtime SA is created locally (L-RUN), not here; only its account id is named, so the email follows
# whatever project id the bootstrap produced. The default is this PR's proposal; L-RUN creates the SA
# under this id, or overrides it here.
variable "api_service_account_id" {
  type        = string
  default     = "ecofolk-api"
  description = "Account id (the part before @) of the Cloud Run API's runtime service account in the dev project."
}

# Issue #20: the dev web app's bare hostname, added to the auth config's authorized domains next to
# localhost. Default null: the Hosting site's <site>.web.app (#22) is used instead, so the keyless apply,
# which sets only TF_VAR_project_id, still runs; set TF_VAR_web_host once a custom dev domain exists.
variable "web_host" {
  type        = string
  default     = null
  description = "Bare hostname of the dev web app, for the auth config's authorized domains. Null: the Hosting site's <site>.web.app."
}

# Issue #2 (Architect name default, 2026-10-16): the ops scheduler SA is created locally (L1(a), ef#885)
# under exactly this id; only the id is named here, so the email follows the project id. #14's start/stop
# jobs use the same account.
variable "ops_scheduler_service_account_id" {
  type        = string
  default     = "ops-scheduler"
  description = "Account id (the part before @) of the ops scheduler service account in the dev project; runs the nightly Cloud SQL export (#2) and the off-hours stop and start (#14)."
}
