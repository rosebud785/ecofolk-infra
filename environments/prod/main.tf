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
# Wired (Architect SPEC OK on #143, 2026-11-02), the modules added since #12, mirroring dev's calls:
# migrate_job (#140, ecofolk#1169), secrets (#32, container names only), web_hosting (#22), idle_sit_sweep
# (#17, ecofolk#460) and sync_usgs_water (#98), both schedulers inside the #99 America/Chicago window rule.
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

# Same keyless ADC as `google`, no credentials argument; used only by modules/web_hosting (#22, #143).
provider "google-beta" {
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
  # ecofolk#1169 (#143): the migrate job's keyless IAM database user (CLOUD_IAM_SERVICE_ACCOUNT, no password),
  # as in dev. A SQL user, not IAM: the service account itself is L-RUN.
  migrate_service_account_email = var.migrate_service_account_email

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

# The API's one base URL for the schedulers' api_url (so each job's uri AND OIDC audience), the same
# DETERMINISTIC run.app form dev uses (#114): https://SERVICE-PROJECT_NUMBER.REGION.run.app, not
# module.cloudrun_api.uri (the hash form, a different string). The project number is read at plan time, so it
# never appears in this public repo.
data "google_project" "this" {
  project_id = local.project_id
}

locals {
  api_base_url = "https://${module.cloudrun_api.name}-${data.google_project.this.number}.${module.project.region}.run.app"
}

# Schema migrator (ecofolk#1169, #140; prod wiring #143): a Cloud Run Job on the API's image, mirroring dev's
# call. Same Direct VPC egress subnet as the API; runs as the keyless migrate SA, which module.cloudsql makes a
# Cloud SQL IAM DB user. The image stays the placeholder; the deploy script owns it. timeout_seconds stays the
# module default (600). Non-secret env_vars only; the one secret ref is the ingest password the migrator sets.
#
# LOCAL FOLLOW-UP (L-RUN, go-live): create the migrate SA in ecofolk-prod with no key and supply its email as
# var.migrate_service_account_email; its grants are listed in modules/migrate_job/main.tf. IAM is not managed
# in this public repo.
module "migrate_job" {
  source          = "../../modules/migrate_job"
  project_id      = local.project_id
  env             = "prod"
  region          = module.project.region
  service_account = var.migrate_service_account_email
  network         = module.network.network_id
  subnetwork      = module.network.subnet_id

  env_vars = {
    DB_HOST                     = module.cloudsql.private_ip_address
    DB_NAME                     = module.cloudsql.database_name
    DB_IAM_USER                 = trimsuffix(var.migrate_service_account_email, ".gserviceaccount.com")
    DB_INSTANCE_CONNECTION_NAME = module.cloudsql.connection_name
    # The API's runtime DB user (config.ts default), as in dev (ecofolk#1180).
    DB_RUNTIME_USER = "ecofolk"
  }

  secret_env = {
    POSTGRES_INGEST_PASSWORD = module.secrets.secret_ids["POSTGRES_INGEST_PASSWORD"]
  }

  depends_on = [module.project, module.network, module.cloudsql]
}

# Idle-sit sweep (#17, ecofolk#460; prod wiring #143): one Cloud Scheduler job POSTs
# {api}/internal/sweep-idle-sits with a Google-signed OIDC ID token for the invoker SA. Prod passes dev's
# 0 5-21/2 * * * (America/Chicago), not the module default 0 */2 * * *, which runs inside the #99 window
# (22:15–04:45 CT, docs/alerting-policy.md). Prod has no off-hours stop, but every environment keeps the rule.
#
# LOCAL FOLLOW-UP (L-RUN, go-live): create the invoker SA in ecofolk-prod with no roles and supply its email as
# var.sweep_invoker_service_account_email. IAM is not managed in this public repo.
module "idle_sit_sweep" {
  source           = "../../modules/idle_sit_sweep"
  project_id       = local.project_id
  env              = "prod"
  region           = module.project.region
  api_url          = local.api_base_url
  invoker_sa_email = var.sweep_invoker_service_account_email
  sweep_schedule   = "0 5-21/2 * * *"

  depends_on = [module.project]
}

# sync-usgs-water (#98; prod wiring #143): one Cloud Scheduler job POSTs {api}/internal/sync-usgs-water at the
# module's fixed 0 5,11,17 * * * America/Chicago, outside the #99 window. Same OIDC pattern and the SAME invoker
# SA as the sweep above; no new SA, binding or actAs here.
module "sync_usgs_water" {
  source           = "../../modules/sync_usgs_water"
  project_id       = local.project_id
  env              = "prod"
  region           = module.project.region
  api_url          = local.api_base_url
  invoker_sa_email = var.sweep_invoker_service_account_email

  depends_on = [module.project]
}

# sync-health (ecofolk-infra#156, ecofolk#1349): one Cloud Scheduler job POSTs {api}/internal/sync-health daily at
# 07:15 America/Chicago (the app's registry cadence, after the other syncs), outside the #99 window. Same OIDC pattern and SAME invoker SA as the jobs above; no new SA,
# binding or actAs here. The alert on its `sync_health_failed` lines is in module.monitoring.
module "sync_health" {
  source           = "../../modules/sync_health"
  project_id       = local.project_id
  env              = "prod"
  region           = module.project.region
  api_url          = local.api_base_url
  invoker_sa_email = var.sweep_invoker_service_account_email

  depends_on = [module.project]
}

# Secret Manager secret CONTAINERS only, no values (#32, Architect ruling on ecofolk#399; prod wiring #143):
# the module's default secret_names, the same list dev uses, one user-managed replica each in Montréal.
#
# LOCAL FOLLOW-UP (ecofolk#936, go-live): add each secret's value (a version) by hand, never in this repo.
# LOCAL FOLLOW-UP (L-RUN, ecofolk#890): roles/secretmanager.secretAccessor per named secret for the runtime and
# migrate SAs. IAM is not managed in this public repo.
module "secrets" {
  source     = "../../modules/secrets"
  project_id = local.project_id
  region     = module.project.region
  env        = "prod"

  depends_on = [module.project]
}

# Firebase Hosting site for the web build (#22; prod wiring #143). Static files only, so no region. Deploys,
# firebase.json and the custom domain are not here (ecofolk#408, ecofolk#670).
module "web_hosting" {
  source     = "../../modules/web_hosting"
  project_id = local.project_id
  env        = "prod"

  providers = {
    google-beta = google-beta
  }

  depends_on = [module.project]
}

# Firebase Auth / Identity Platform config (#20): email + password on, no IdP configs. web_host falls back to
# the Hosting site's <site>.web.app (#22) while var.web_host is unset, as in dev (#143).
module "auth" {
  source     = "../../modules/auth"
  project_id = local.project_id
  web_host   = coalesce(var.web_host, module.web_hosting.default_host)

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
  web_host                         = coalesce(var.web_host, module.web_hosting.default_host)
  sql_instance_name                = module.cloudsql.instance_name
  sql_export_job_name              = module.cloudsql.export_job_name

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


output "web_default_url" {
  value       = module.web_hosting.default_url
  description = "The prod web app's Hosting URL (https://<site>.web.app), for the API's CORS allowlist."
}

# Every Cloud Scheduler job in the prod composition (#99), for the prod root tests (#144): each must be
# America/Chicago and outside the 22:15–04:45 CT window.
output "scheduler_jobs" {
  value = concat(
    module.cloudsql.scheduler_jobs,
    module.idle_sit_sweep.scheduler_jobs,
    module.sync_usgs_water.scheduler_jobs,
    module.sync_health.scheduler_jobs,
  )
  description = "Every Cloud Scheduler job in the prod composition: name, schedule and time_zone (#99)."
}

# Every resource name in the prod composition, as <type>/<name>, for the prod root tests (#144): none may carry a
# qa or dev name (the other side of environments/qa's collision test).
output "resource_names" {
  value = concat(
    module.project.resource_names,
    module.network.resource_names,
    module.artifact_registry.resource_names,
    module.cloudsql.resource_names,
    module.cloudrun_api.resource_names,
    module.migrate_job.resource_names,
    module.idle_sit_sweep.resource_names,
    module.sync_usgs_water.resource_names,
    module.sync_health.resource_names,
    module.secrets.resource_names,
    module.auth.resource_names,
    module.media_bucket.resource_names,
    module.web_hosting.resource_names,
    module.monitoring.resource_names,
  )
  description = "Every resource name in the prod composition, as <type>/<name> (#144)."
}

output "cloudsql_protections" {
  value       = module.cloudsql.protections
  description = "Cloud SQL deletion protection, PITR and ops windows as planned (#144)."
}

output "authorized_domains" {
  value       = module.auth.authorized_domains
  description = "The auth config's authorized domains (#144)."
}

output "project_region" {
  value       = module.project.region
  description = "The pinned region every prod module takes (#144)."
}
