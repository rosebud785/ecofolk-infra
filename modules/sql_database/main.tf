# main.tf — one environment's own database on an EXISTING Cloud SQL instance (ecofolk-infra#13, row C13).
#
# The QA/test environment is a namespace inside ecofolk-dev (Andy, 2026-10-09): it reuses dev's instance
# (modules/cloudsql, called only from environments/dev) and gets its own database and its own DB user name
# here. This module never declares a google_sql_database_instance; environments/qa's test asserts that
# for the whole qa root.
#
# What is here: one google_sql_database, ecofolk_<env> (ecofolk_qa). The user name is only a name, an
# output: no google_sql_user and no random_password, because Terraform never manages secret values (same
# as modules/cloudsql). The user and its password are created out of band (pipeline design §5).
#
# Shares the instance, so it shares its fate: #14's off-hours stop and #15's billing unlink of ecofolk-dev
# take this database down with dev's. That is accepted for a test env (#13).
#
# Needs sqladmin.googleapis.com, which environments/dev's modules/project already enables.
#
# LOCAL FOLLOW-UP (L-SQL, #13): create the built-in Postgres user output user_name on the instance, with
# its password out of band (pipeline design §5, never in Terraform), and give it ownership of this database
# only. Not IAM, and not in this public repo.
locals {
  # #13: a namespace env gets _<env>. dev and prod keep "ecofolk", which modules/cloudsql owns, so the
  # env validation refuses them here.
  env_suffix = contains(["dev", "prod"], var.env) ? "" : "-${var.env}"
  db_suffix  = replace(local.env_suffix, "-", "_")
}

resource "google_sql_database" "this" {
  project  = var.project_id
  name     = "ecofolk${replace(local.env_suffix, "-", "_")}"
  instance = var.instance_name
}
