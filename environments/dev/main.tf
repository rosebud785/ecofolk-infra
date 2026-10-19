# dev environment root module — BUILD_PLAN.md §11.1's ecofolk-dev project.
#
# Keyless CI (ef#827, Architect design §6): there is NO credentials argument on the provider and no key
# file anywhere. In CI, google-github-actions/auth exchanges the job's GitHub OIDC token through Workload
# Identity Federation for a short-lived access token and exports it as Application Default Credentials;
# this provider and the GCS backend both pick that up. See .github/workflows/infra.yml. Run by hand,
# `gcloud auth application-default login` supplies the same.
#
# The backend's bucket is deliberately NOT written here: a backend block cannot take variables, and the
# bucket id is an environment fact (the §5 bootstrap output, held in the repo variable
# TF_STATE_BUCKET), not source. It is supplied at init time:
#   terraform init -backend-config="bucket=<bucket>"
# and CI's `terraform init -backend=false` (validate jobs) never needs it.
#
# `region` is deliberately NOT set on the provider, nor passed to the module: the module's own default
# (northamerica-northeast1, ef#391) is the single source of truth, and a provider-level region would be a
# second place that has to agree with it. Every regional resource takes its region from that module.
terraform {
  backend "gcs" {
    prefix = "dev"
  }
}

provider "google" {
  project = var.project_id
}

# Same keyless ADC as `google`, no credentials argument; used only by modules/web_hosting (#22).
provider "google-beta" {
  project = var.project_id
}

module "project" {
  source     = "../../modules/project"
  project_id = var.project_id
}

# VPC + Private Service Access (issue #1). Region comes from module.project, the single source of the
# pin; depends_on so the compute and servicenetworking APIs are enabled first.
module "network" {
  source     = "../../modules/network"
  project_id = var.project_id
  region     = module.project.region

  depends_on = [module.project]
}

# Cloud SQL Postgres 16, private IP only (issue #18). Region is the module's own pinned default, per the
# #18 spec; depends_on so sqladmin is enabled and the PSA peering exists before the instance asks for a
# private IP.
#
# Issue #2 adds the maintenance and backup windows, PITR (7 days), and the nightly export to
# <project>-sql-exports, run by Cloud Scheduler as the ops-scheduler service account.
# LOCAL FOLLOW-UP (L1(a), ef#885): create ops-scheduler and its bindings; the list is in
# modules/cloudsql/export.tf. IAM is not managed in this public repo.
module "cloudsql" {
  source                       = "../../modules/cloudsql"
  project_id                   = var.project_id
  private_network              = module.network.network_self_link
  export_service_account_email = "${var.ops_scheduler_service_account_id}@${var.project_id}.iam.gserviceaccount.com"

  depends_on = [module.project, module.network]
}

# Dev Cloud SQL off-hours stop and start (issue #14, Architect SPEC OK 2026-10-16, amended): two Cloud
# Scheduler jobs PATCH activationPolicy, NEVER at 22:15 CT and ALWAYS at 04:45 CT, before #2's 05:00 CT
# maintenance window. They run as ops-scheduler, the same account as #2's export. Dev only: there is no call
# in environments/prod, and the module refuses a *-prod project. enable_off_hours stays at its default (true).
# This also stops the QA namespace (#13 shares the instance); that's intended.
#
# LOCAL FOLLOW-UP (L1(a), ef#885): grant ops-scheduler roles/cloudsql.editor on ecofolk-dev only. IAM is not
# managed in this public repo.
module "sql_off_hours" {
  source                = "../../modules/sql_off_hours"
  project_id            = var.project_id
  region                = module.project.region
  instance_name         = module.cloudsql.instance_name
  service_account_email = "${var.ops_scheduler_service_account_id}@${var.project_id}.iam.gserviceaccount.com"

  depends_on = [module.project]
}

# The API on Cloud Run v2, scale-to-zero (issue #19). Region from module.project, egress into the subnet
# from module.network; depends_on so run.googleapis.com is enabled and the subnet exists first. The image
# stays the module's placeholder: deploys (ef#408) own it.
#
# network/subnetwork are the relative resource names (.id), not the self-links: Cloud Run v2 400s on an
# https self-link (ecofolk-infra#45). Cloud SQL above stays on network_self_link, which its API accepts.
#
# LOCAL FOLLOW-UP (L-RUN), in this order; IAM is not managed in this public repo (ecofolk-infra#44):
#   1. Create the runtime service account var.api_service_account_id with NO roles at this stage: for now
#      it is only the identity the service runs as (the placeholder image touches no database or secret).
#   2. Grant the apply identity (tf-apply) roles/iam.serviceAccountUser ON THAT ONE SERVICE ACCOUNT only,
#      never project-wide. Without it the first apply of this block 403s on iam.serviceaccounts.actAs
#      (main's Infra apply was red for that from 10-11 to 10-13, #19).
#   3. Deferred: the `allUsers` -> roles/run.invoker binding on the service to ef#408 (first real deploy);
#      roles/cloudsql.client and roles/secretmanager.secretAccessor (per named secret, see module.secrets
#      below) to ef#399 / ecofolk#890.
module "cloudrun_api" {
  source          = "../../modules/cloudrun_api"
  project_id      = var.project_id
  region          = module.project.region
  service_account = "${var.api_service_account_id}@${var.project_id}.iam.gserviceaccount.com"
  network         = module.network.network_id
  subnetwork      = module.network.subnet_id

  depends_on = [module.project, module.network]
}

# Idle-sit sweep (issue #17, Architect's OIDC redesign on PR #86): one Cloud Scheduler job POSTs
# {api}/internal/sweep-idle-sits with a Google-signed OIDC ID token for the sweep-invoker SA, audience =
# that URL; the API verifies it (ecofolk#1092). No static secret and no header in Terraform. Dev passes
# 0 5-21/2 * * * (America/Chicago) instead of the module's every-2-hours default, so no sweep runs while
# #14 has dev Cloud SQL stopped (22:15–04:45 CT); an overnight sweep would be a DB connection failure that
# #24's alert pages on. Details: modules/idle_sit_sweep/README.md.
#
# LOCAL FOLLOW-UP (ecofolk#460 / L1(a)), IAM is not managed in this public repo: create the SA
# var.sweep_invoker_service_account_id with no roles, and confirm tf-apply can actAs it; add the ef#395
# inventory line.
module "idle_sit_sweep" {
  source           = "../../modules/idle_sit_sweep"
  project_id       = var.project_id
  region           = module.project.region
  api_url          = module.cloudrun_api.uri
  invoker_sa_email = "${var.sweep_invoker_service_account_id}@${var.project_id}.iam.gserviceaccount.com"
  sweep_schedule   = "0 5-21/2 * * *"

  depends_on = [module.project]
}

# Secret Manager secret CONTAINERS only, no values (issue #32, Architect ruling on ecofolk#399): the four
# default names in modules/secrets, one user-managed replica each in Montréal. Region is module.project's
# pin; depends_on so secretmanager.googleapis.com is enabled first.
#
# LOCAL FOLLOW-UP (ecofolk#936): add each secret's value (a version) by hand. Never in this repo: C7 refuses
# google_secret_manager_secret_version outside local-only/.
# LOCAL FOLLOW-UP (L-RUN, ecofolk#890): roles/secretmanager.secretAccessor for the API's runtime service
# account (var.api_service_account_id) on each of these secrets only. IAM is not managed in this public repo.
module "secrets" {
  source     = "../../modules/secrets"
  project_id = var.project_id
  region     = module.project.region
  env        = "dev"

  depends_on = [module.project]
}

# Firebase Auth / Identity Platform config (issue #20): email + password on, no anonymous, no IdP
# configs (OAuth providers are local follow-up L-AUTH). depends_on so identitytoolkit is enabled first.
# web_host falls back to the Hosting site's <site>.web.app (#22) while var.web_host is unset.
module "auth" {
  source     = "../../modules/auth"
  project_id = var.project_id
  web_host   = coalesce(var.web_host, module.web_hosting.default_host)

  depends_on = [module.project]
}

# Private GCS bucket for user media, photos and audio (issue #21, Architect re-spec 2026-10-09: GCS in
# Montréal, not Cloudflare R2). Applied by this root's keyless CI apply like everything else here. Location
# is the module's own pinned default; depends_on so storage.googleapis.com is enabled first.
#
# LOCAL FOLLOW-UP (L-RUN, ecofolk#890): roles/storage.objectAdmin for the API's runtime service account
# (var.api_service_account_id) on this bucket only. IAM is not managed in this public repo.
module "media_bucket" {
  source     = "../../modules/media_bucket"
  project_id = var.project_id
  env        = "dev"

  depends_on = [module.project]
}

# Firebase Hosting site for the web build (issue #22, Architect re-spec 2026-10-09: Firebase Hosting, not
# Cloudflare Pages). Static files only, served from the CDN, so no region (modules/web_hosting/README.md).
# Deploys, firebase.json and the custom domain are not here (ecofolk#408, ecofolk#670). depends_on so
# firebase and firebasehosting are enabled first.
module "web_hosting" {
  source     = "../../modules/web_hosting"
  project_id = var.project_id

  providers = {
    google-beta = google-beta
  }

  depends_on = [module.project]
}

# Dev billing kill-switch (issue #15): the ecofolk-dev-killswitch topic and a Cloud Functions (2nd gen)
# function that unlinks billing from ecofolk-dev once the dedicated dev budget's gross spend reaches 100%.
# Dev only, never prod: there is no call in environments/prod, and C7 (policy/billing_killswitch.rego)
# refuses a *-prod id on the allowlist. Names, the allowlist, the budget name and the threshold are the
# module's defaults (Architect, #15). depends_on so run, cloudbuild, artifactregistry and storage are on.
#
# LOCAL FOLLOW-UP (ecofolk#885, L1(b)): create budget ecofolk-dev-killswitch ($25/month, scoped to ecofolk-dev,
# --credit-types-treatment=exclude-all-credits) and point it at this topic; create the runtime SA
# ecofolk-killswitch; grant it roles/billing.projectManager on ecofolk-dev only, and the trigger grants listed
# in modules/billing_killswitch/main.tf. IAM is not managed in this public repo.
module "billing_killswitch" {
  source     = "../../modules/billing_killswitch"
  project_id = var.project_id
  region     = module.project.region

  depends_on = [module.project]
}

# Alerts (#24), uptime checks on the API's /health and the web root (#5), and the dashboard (#6), wired the
# way PR #84 wires prod (issue #90, Architect ruling row 3256). The uptime checks probe only hosts that
# already exist in dev: the API's Cloud Run run.app host, and the same web host module.auth uses (the
# Hosting site's <site>.web.app while var.web_host is unset). db_max_connections stays the module default,
# 25 = db-f1-micro, modules/cloudsql's default tier.
#
# Dev alerts go to the email channel Andy made by hand for ef#894, same as prod (Architect ruling on #94,
# 2026-10-19; it supersedes the earlier "dev passes [] and pages nobody" line in the #90 spec). The value
# comes from repo variable ALERT_CHANNEL_IDS (infra-apply.yml), not from a committed tfvars. #14 stops dev
# Cloud SQL 22:15–04:45 CT, so no DB-touching job may run in that window (docs/alerting-policy.md).
#
# LOCAL FOLLOW-UP (L-ALERT): supply the two log filters (db_connection_failure_log_filter,
# media_write_failure_log_filter) to the dev apply via repo variables. ALERT_CHANNEL_IDS already holds the
# email channel. No IAM.
module "monitoring" {
  source                           = "../../modules/monitoring"
  project_id                       = var.project_id
  api_service_name                 = module.cloudrun_api.name
  notification_channels            = var.alert_notification_channels
  db_connection_failure_log_filter = var.db_connection_failure_log_filter
  media_write_failure_log_filter   = var.media_write_failure_log_filter
  api_host                         = trimprefix(module.cloudrun_api.uri, "https://")
  web_host                         = coalesce(var.web_host, module.web_hosting.default_host)
  sql_instance_name                = module.cloudsql.instance_name

  depends_on = [module.project]
}

# Firebase is already attached to ecofolk-dev (Andy, 2026-10-15: GET firebase.googleapis.com/v1beta1/
# projects/ecofolk-dev returned 200), so the project is adopted into state rather than created; a create
# would fail with ALREADY_EXISTS. No import for google_firebase_hosting_site.web: attaching Firebase
# makes a default site named "ecofolk-dev", while this one is "ecofolk-dev-web", a genuine create.
import {
  to = module.web_hosting.google_firebase_project.this
  id = "projects/ecofolk-dev"
}

output "auth_domain" {
  value       = module.auth.auth_domain
  description = "Firebase auth domain for the web build's config."
}

output "web_default_url" {
  value       = module.web_hosting.default_url
  description = "The dev web app's Hosting URL (https://<site>.web.app), for the API's CORS allowlist."
}

output "billing_killswitch_topic" {
  value       = module.billing_killswitch.topic_id
  description = "The budget topic the local ef#885 script points budget ecofolk-dev-killswitch at (#15)."
}

output "uptime_check_ids" {
  value       = module.monitoring.uptime_check_ids
  description = "Uptime check IDs of the dev API /health and web root checks (#5)."
}
