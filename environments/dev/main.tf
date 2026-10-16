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
module "cloudsql" {
  source          = "../../modules/cloudsql"
  project_id      = var.project_id
  private_network = module.network.network_self_link

  depends_on = [module.project, module.network]
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
