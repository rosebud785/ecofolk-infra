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
#      roles/cloudsql.client and roles/secretmanager.secretAccessor (per named secret) to ef#399.
module "cloudrun_api" {
  source          = "../../modules/cloudrun_api"
  project_id      = var.project_id
  region          = module.project.region
  service_account = "${var.api_service_account_id}@${var.project_id}.iam.gserviceaccount.com"
  network         = module.network.network_id
  subnetwork      = module.network.subnet_id

  depends_on = [module.project, module.network]
}

# Firebase Auth / Identity Platform config (issue #20): email + password on, no anonymous, no IdP
# configs (OAuth providers are local follow-up L-AUTH). depends_on so identitytoolkit is enabled first.
module "auth" {
  source     = "../../modules/auth"
  project_id = var.project_id
  web_host   = var.web_host

  depends_on = [module.project]
}

output "auth_domain" {
  value       = module.auth.auth_domain
  description = "Firebase auth domain for the web build's config."
}
