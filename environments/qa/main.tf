# qa environment root module — the Cloud QA/test environment, as a namespace inside ecofolk-dev
# (ecofolk-infra#13; Andy, 2026-10-09, answering ARCHITECTURE §8.3 OPEN 2: not a third project).
#
# Its own root and its own state: prefix `qa` in the same state bucket as dev (the bucket is supplied at
# init, as for dev: terraform init -backend-config="bucket=<bucket>"). Keyless like dev: no credentials
# argument and no key file anywhere.
#
# What QA reuses from dev, by lookup (data sources, never resources): the VPC and subnet (C1, #1), the
# Cloud SQL INSTANCE (#18) and the media bucket (#21). What QA owns: its own database and DB user name
# (modules/sql_database), its own Cloud Run service (modules/cloudrun_api with env = "qa", so
# ecofolk-api-qa), and its own prefix, qa/, in dev's media bucket. Every name QA creates ends in -qa or _qa,
# and environments/qa/tests asserts that none collides with dev's and that this root never declares a
# google_sql_database_instance.
#
# Consequences (#13), accepted for a test env and matching its ops hours:
#   - QA shares dev's SQL instance, so #14's off-hours stop (22:15–04:45 CT) stops QA too, and #15's
#     billing unlink of ecofolk-dev takes QA down with dev;
#   - there is no project-level isolation: a bad dev apply can touch QA resources. C7's env rule
#     (policy/env.rego) and this root's separate state are the guard.
#
# Not applied by CI: .github/workflows/infra-apply.yml applies environments/dev only. This root is planned
# and applied only from main, after a reviewed merge (README: Plan and apply).
#
# No new IAM or WIF (#13): tf-apply's dev-project roles cover it, and the service runs as dev's existing
# runtime SA (variables.tf).
#
# LOCAL FOLLOW-UP (L-SQL, #13): create the Postgres user output db_user_name on dev's instance, with its
# password out of band (pipeline design §5); see modules/sql_database/main.tf.
# LOCAL FOLLOW-UP (L-RUN, ef#408): as for dev, allUsers -> roles/run.invoker on ecofolk-api-qa at the first
# real deploy, and the deploy sets the service's database, user and media prefix from this root's outputs.
# Dev's runtime SA already holds (or will hold, L-RUN / ecofolk#890) the bucket and database access QA needs;
# nothing new is bound here.
terraform {
  backend "gcs" {
    prefix = "qa"
  }
}

provider "google" {
  project = var.project_id
}

locals {
  env = "qa"

  # Objects QA writes in dev's media bucket go under this prefix (#13, Architect wording fix 2026-10-16:
  # a prefix in the GCS media bucket, not R2). The bucket's no-age-delete rule (#21) applies to it too.
  media_prefix = "${local.env}/"
}

# Dev's network (C1). Lookups fail the plan if dev's network isn't there, rather than creating another.
data "google_compute_network" "dev" {
  name = var.dev_network_name
}

data "google_compute_subnetwork" "dev" {
  name   = "${var.dev_network_name}-${var.region}"
  region = var.region
}

# Dev's Cloud SQL instance (#18). QA reads it, never declares one.
data "google_sql_database_instance" "dev" {
  name = var.dev_sql_instance_name
}

# Dev's media bucket (#21), <project_id>-media. QA gets a prefix in it, not a bucket.
data "google_storage_bucket" "dev_media" {
  name = "${var.project_id}-media"
}

# QA's own database on dev's instance (#13): ecofolk_qa, with the user name ecofolk_qa_app (a name only).
module "sql_database" {
  source        = "../../modules/sql_database"
  project_id    = var.project_id
  instance_name = data.google_sql_database_instance.dev.name
  env           = local.env
}

# QA's own Cloud Run service, ecofolk-api-qa, scale-to-zero like dev's (#19), with Direct VPC egress into
# dev's subnet. network/subnetwork are the relative resource names (.id), not self-links (#45). The image
# stays the module's placeholder: deploys (ef#408) own it.
module "cloudrun_api" {
  source          = "../../modules/cloudrun_api"
  project_id      = var.project_id
  region          = var.region
  env             = local.env
  service_account = "${var.api_service_account_id}@${var.project_id}.iam.gserviceaccount.com"
  network         = data.google_compute_network.dev.id
  subnetwork      = data.google_compute_subnetwork.dev.id
}

output "api_uri" {
  value       = module.cloudrun_api.uri
  description = "The QA API's run.app URI. Not callable by the public until L-RUN adds the invoker binding (ef#408)."
}

output "sql_connection_name" {
  value       = data.google_sql_database_instance.dev.connection_name
  description = "Connection name of dev's instance, which QA shares (<project>:<region>:<instance>)."
}

output "database_name" {
  value       = module.sql_database.database_name
  description = "QA's own database on dev's instance (ecofolk_qa)."
}

output "db_user_name" {
  value       = module.sql_database.user_name
  description = "QA's own DB user name (ecofolk_qa_app). The user and its password are created out of band (L-SQL)."
}

output "media_bucket" {
  value       = data.google_storage_bucket.dev_media.name
  description = "Dev's media bucket, which QA shares under media_prefix."
}

output "media_prefix" {
  value       = local.media_prefix
  description = "QA's object prefix in the media bucket (qa/)."
}

# Every resource name in this composition (#13), as <type>/<name>, for tests/qa_isolation.tftest.hcl: none
# may collide with environments/dev's resource_names. Every module call must be listed here; the test
# fails otherwise.
output "resource_names" {
  value = concat(
    module.sql_database.resource_names,
    module.cloudrun_api.resource_names,
  )
  description = "Every resource name in the qa composition, as <type>/<name> (#13's dev/qa collision test)."
}
