# prod environment root module — BUILD_PLAN.md §11.1's ecofolk-prod project.
#
# Issue #12: the prod composition, the same modules as dev at prod sizing, so `validate` and C7's prod
# rules prove they compose before go-live day. CI only validates this root (ci.yml's validate job); no
# workflow plans or applies it (scripts/check-workflows.sh rule 5, pipeline design §6.2). ecofolk-prod
# stays unlinked from billing until go-live.
#
# Wired (Architect SPEC OK on #12, 2026-10-16): project, network (C1, #1), cloudsql (ef#398, #18) with C2's
# ops windows, PITR and nightly export (#2), artifact_registry (C4, #4), cloudrun_api (ef#400, #19), auth
# (#20), media_bucket (#21, GCS; ef#926 supersedes ef#401's R2) and monitoring (#24, C5 #5, C6 #6).
# Dev-only modules are deliberately NOT here: sql_off_hours (#14) and billing_killswitch (#15) refuse a
# *-prod project.
#
# Same keyless ADC as dev: no credentials argument on the provider, no key file anywhere. `region` is
# deliberately never set on the provider: module.project's pinned default (ef#391) is the single source.

# TODO(go-live): no prod state bucket exists yet. Uncomment once it does, and supply the bucket at init
# time like dev (`terraform init -backend-config="bucket=<bucket>"`); `init -backend=false` never needs it.
# terraform {
#   backend "gcs" {
#     prefix = "prod"
#   }
# }

provider "google" {
  project = local.project_id
}

# env (#13): every module that names or labels a resource takes env = "prod". Prod's names are unchanged;
# only a namespace env (qa) suffixes names.

locals {
  project_id = "ecofolk-prod"
}

module "project" {
  source     = "../../modules/project"
  project_id = local.project_id
}

# VPC + Private Service Access (C1, #1). Region from module.project, the single source of the pin.
module "network" {
  source     = "../../modules/network"
  project_id = local.project_id
  env        = "prod"
  region     = module.project.region

  depends_on = [module.project]
}

# Cloud SQL Postgres 16, private IP only (ef#398, #18), with C2's (#2) maintenance and backup windows, PITR
# on with 7 days of transaction logs, and the nightly export. PITR and its retention are fixed in the
# module (not variables), so prod gets #2's settings by calling it: this ticks #12's go-live checkbox.
#
# deletion_protection = true is the module default; it is written here so the prod intent is explicit.
# tier is a literal on the C7 allowlist (policy/data.json), as C7b (#39) requires of every call site.
#
# LOCAL FOLLOW-UP (L1(a), ef#885): create ops-scheduler in ecofolk-prod and its bindings; the list is in
# modules/cloudsql/export.tf. IAM is not managed in this public repo.
module "cloudsql" {
  source              = "../../modules/cloudsql"
  project_id          = local.project_id
  env                 = "prod"
  private_network     = module.network.network_self_link
  deletion_protection = true
  # go-live: confirm tier (cost review)
  tier                         = "db-f1-micro"
  export_service_account_email = "${var.ops_scheduler_service_account_id}@${local.project_id}.iam.gserviceaccount.com"

  depends_on = [module.project, module.network]
}

# Docker repo for the API image, with cleanup policies (C4, #4).
module "artifact_registry" {
  source        = "../../modules/artifact_registry"
  project_id    = local.project_id
  env           = "prod"
  region        = module.project.region
  repository_id = "ecofolk-images"

  depends_on = [module.project]
}

# The API on Cloud Run v2, scale-to-zero (ef#400, #19). max_instance_count stays the module default (3),
# inside C7's prod cap of 5. network/subnetwork are the .id, not the self-link (#45).
#
# LOCAL FOLLOW-UP (L-RUN), as for dev (environments/dev/main.tf): create the runtime service account
# var.api_service_account_id in ecofolk-prod with no roles; grant tf-apply roles/iam.serviceAccountUser on
# that one service account only; later, allUsers -> roles/run.invoker on the service (ef#408) and
# roles/cloudsql.client (ef#399). IAM is not managed in this public repo.
module "cloudrun_api" {
  source          = "../../modules/cloudrun_api"
  project_id      = local.project_id
  env             = "prod"
  region          = module.project.region
  service_account = "${var.api_service_account_id}@${local.project_id}.iam.gserviceaccount.com"
  network         = module.network.network_id
  subnetwork      = module.network.subnet_id

  depends_on = [module.project, module.network]
}

# Firebase Auth / Identity Platform config (#20): email + password on, no IdP configs.
module "auth" {
  source     = "../../modules/auth"
  project_id = local.project_id
  web_host   = var.web_host

  depends_on = [module.project]
}

# Private GCS media bucket in Montréal (#21).
#
# LOCAL FOLLOW-UP (L-RUN, ecofolk#890): roles/storage.objectAdmin for the API's runtime service account on
# this bucket only. IAM is not managed in this public repo.
module "media_bucket" {
  source     = "../../modules/media_bucket"
  project_id = local.project_id
  env        = "prod"

  depends_on = [module.project]
}

# Alerts (#24), uptime checks on the API's /health and the web root (C5, #5), and the dashboard (C6, #6).
# Channels are IDs only, made by hand (L-ALERT); the log filters come from L-ALERT too. The API host is the
# Cloud Run service's run.app host. db_max_connections stays the module default, 25 = db-f1-micro, the
# tier above.
module "monitoring" {
  source                           = "../../modules/monitoring"
  project_id                       = local.project_id
  env                              = "prod"
  api_service_name                 = module.cloudrun_api.name
  notification_channels            = var.alert_notification_channels
  db_connection_failure_log_filter = var.db_connection_failure_log_filter
  media_write_failure_log_filter   = var.media_write_failure_log_filter
  api_host                         = trimprefix(module.cloudrun_api.uri, "https://")
  web_host                         = var.web_host
  sql_instance_name                = module.cloudsql.instance_name

  depends_on = [module.project]
}

output "auth_domain" {
  value       = module.auth.auth_domain
  description = "Firebase auth domain for the prod web build's config."
}

output "sql_connection_name" {
  value       = module.cloudsql.connection_name
  description = "Prod Cloud SQL instance connection name, for the Cloud SQL connector."
}

