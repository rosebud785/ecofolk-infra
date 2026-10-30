# main.tf — Cloud SQL for PostgreSQL 16, private IP only, in Montréal (ecofolk-infra#18, ef#398).
#
# What is here: one ENTERPRISE-edition Postgres 16 instance with no public IP, attached to the VPC from
# modules/network through its Private Service Access range; automated backups on; IAM database
# authentication on; and one database, `ecofolk`. C2 (#2) adds the ops settings below (maintenance and
# backup windows, PITR) and, in export.tf, a nightly export to a bucket that outlives the instance.
#
# What is deliberately NOT here (Architect spec on #18):
#   - no random_password, and no google_sql_user of type BUILT_IN: Terraform never manages secret values.
#     The ONE user it does manage is the migrate job's CLOUD_IAM_SERVICE_ACCOUNT user (ecofolk#1169): keyless,
#     no password, nothing secret. Other app and IAM database users are local follow-up L-SQL;
#   - the `postgis` and `vector` extensions: the app's migrations create them, and Cloud SQL needs no
#     flag for either;
#   - no HA (availability_type stays ZONAL).
#
# The instance bills while idle; C14 (#14, modules/sql_off_hours) stops it out of hours in dev.
#
# Needs sqladmin.googleapis.com (modules/project) and the PSA peering (modules/network); callers order
# them with `depends_on` (see environments/dev/main.tf).
#
# LOCAL FOLLOW-UP (conditional, Architect ruling on PR #38): no role is granted up front. tf-apply has
# roles/editor, which is expected to cover cloudsql.instances.*; the first apply is the measurement. If it
# returns a 403, that goes to the Architect and the narrowest role is added locally (same route as #35).
# LOCAL FOLLOW-UP (L-SQL): the app's DB user (password into Secret Manager, never into Terraform), and
# the IAM DB user for the Cloud Run runtime service account (with roles/cloudsql.client and
# roles/cloudsql.instanceUser on the project).
resource "google_sql_database_instance" "postgres" {
  project          = var.project_id
  name             = "${var.instance_name}${local.env_suffix}"
  region           = var.region
  database_version = "POSTGRES_16"

  # Terraform-side guard: a `destroy` or replacement fails while this is true.
  deletion_protection = var.deletion_protection

  settings {
    # tier is exactly var.tier: C7b (#39, policy/module_vars.rego) checks its literal default and every
    # call site's value against the tier allowlist, so the cost bound stays mechanical.
    edition           = "ENTERPRISE"
    tier              = var.tier
    availability_type = "ZONAL"

    user_labels = {
      env = var.env
    }

    # GCP-side guard, from the same variable: the instance can't be deleted from the console or API either.
    deletion_protection_enabled = var.deletion_protection

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.private_network
    }

    # C2 (#2): Sunday 05:00 CT. Cloud SQL takes the hour in UTC and has no time zone, so see the locals.
    maintenance_window {
      day  = local.maintenance_day
      hour = local.maintenance_hour_utc
    }

    backup_configuration {
      enabled = true
      # C2 (#2): 05:30 CT, in UTC (see the locals).
      start_time = local.backup_start_time_utc

      # C2 (#2), Architect ruling 2026-10-13: PITR on with 7 days of logs, in dev and prod alike. Not
      # variables, so no caller can turn it off.
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = local.transaction_log_retention_days
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  }

  # C14 (#14): modules/sql_off_hours' Scheduler jobs flip settings.activationPolicy (NEVER at 22:15 CT,
  # ALWAYS at 04:45 CT) outside Terraform. Without this, an apply from main while dev is stopped would
  # plan activation_policy back to its default and start the instance again.
  lifecycle {
    ignore_changes = [settings[0].activation_policy]
  }
}

# ecofolk#1169: the migrate job's IAM database user. A CLOUD_IAM_SERVICE_ACCOUNT user has no password, so
# nothing secret is written here; the name is the service account's email without ".gserviceaccount.com"
# (Cloud SQL's form for a service account user). Off (count 0) while migrate_service_account_email is unset.
# cloudsqlsuperuser is a paste step (the pinned provider has no database_roles, see below); the runtime user's DML grants are the migrate CLI's post-step (ecofolk#1180).
resource "google_sql_user" "migrate" {
  count = var.migrate_service_account_email == null ? 0 : 1

  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  name     = trimsuffix(var.migrate_service_account_email, ".gserviceaccount.com")
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"

  # NOT database_roles: the pinned provider (hashicorp/google 5.45.2, the last 5.x) has no such argument on
  # google_sql_user (terraform validate: "An argument named database_roles is not expected here"). The migrator's
  # cloudsqlsuperuser membership (CREATE EXTENSION postgis, vector) is Architect's fallback instead: one
  # `gcloud sql users assign-roles <migrator> --instance=ecofolk-pg --type=CLOUD_IAM_SERVICE_ACCOUNT
  # --database-roles=cloudsqlsuperuser` in Andy's paste (ecofolk#1180 ruling (2a)). Revisit on a provider major bump.
}

resource "google_sql_database" "ecofolk" {
  project  = var.project_id
  name     = "ecofolk${replace(local.env_suffix, "-", "_")}"
  instance = google_sql_database_instance.postgres.name
}

locals {
  # #13: dev and prod keep their names (each owns its project); a namespace env (qa) gets -<env>.
  env_suffix = contains(["dev", "prod"], var.env) ? "" : "-${var.env}"

  # The database's name: "ecofolk" in dev and prod, with an underscore suffix in a namespace env (#13).
  database_name = google_sql_database.ecofolk.name

  # C2 (#2) windows. "CT" is America/Chicago (the zone #14's AC names). Cloud SQL's maintenance hour and
  # backup start are UTC with no DST, so they are pinned to CST (UTC-6): 05:00 CT = 11:00 UTC. Under CDT
  # the same UTC times read 06:00 and 06:30 CT. That still falls after dev's 04:45 CT start (#14) and
  # before ops hours (07:00 CT). A CDT pin (10:00 UTC) would put the winter backup at 04:30 CST, while dev
  # is still stopped, and Cloud SQL skips the backups of a stopped instance.
  maintenance_day                = 7 # Cloud SQL counts 1 = Monday ... 7 = Sunday
  maintenance_hour_utc           = 11
  backup_start_time_utc          = "11:30"
  transaction_log_retention_days = 7
}
