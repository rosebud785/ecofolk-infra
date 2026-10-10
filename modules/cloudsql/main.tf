# main.tf — Cloud SQL for PostgreSQL 16, private IP only, in Montréal (ecofolk-infra#18, ef#398).
#
# What is here: one ENTERPRISE-edition Postgres 16 instance with no public IP, attached to the VPC from
# modules/network through its Private Service Access range; automated backups on; IAM database
# authentication on; and one database, `ecofolk`.
#
# What is deliberately NOT here (Architect spec on #18):
#   - no google_sql_user and no random_password: Terraform never manages secret values. App and IAM
#     database users are local follow-up L-SQL;
#   - no backup window and no point-in-time recovery: those are C2 (#2);
#   - the `postgis` and `vector` extensions: the app's migrations create them, and Cloud SQL needs no
#     flag for either;
#   - no HA (availability_type stays ZONAL).
#
# The instance bills while idle; C14 (#14) stops it out of hours.
#
# Needs sqladmin.googleapis.com (modules/project) and the PSA peering (modules/network); callers order
# them with `depends_on` (see environments/dev/main.tf).
#
# LOCAL FOLLOW-UP: the tf-apply service account needs roles/cloudsql.admin on the project before the
# first apply of this module. IAM is not managed in this public repo.
# LOCAL FOLLOW-UP (L-SQL): the app's DB user (password into Secret Manager, never into Terraform), and
# the IAM DB user for the Cloud Run runtime service account (with roles/cloudsql.client and
# roles/cloudsql.instanceUser on the project).
resource "google_sql_database_instance" "postgres" {
  project          = var.project_id
  name             = var.instance_name
  region           = var.region
  database_version = "POSTGRES_16"

  # Terraform-side guard: a `destroy` or replacement fails while this is true.
  deletion_protection = var.deletion_protection

  settings {
    edition           = "ENTERPRISE"
    tier              = var.tier
    availability_type = "ZONAL"

    # GCP-side guard, from the same variable: the instance can't be deleted from the console or API either.
    deletion_protection_enabled = var.deletion_protection

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.private_network
    }

    backup_configuration {
      enabled = true
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  }
}

resource "google_sql_database" "ecofolk" {
  project  = var.project_id
  name     = local.database_name
  instance = google_sql_database_instance.postgres.name
}

locals {
  database_name = "ecofolk"
}
