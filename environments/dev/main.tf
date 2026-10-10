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
