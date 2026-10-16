# export.tf — nightly export of the database to a bucket that outlives the instance (ecofolk-infra#2, C2).
#
# Why: automated backups (and PITR logs) are deleted along with the instance. A SQL export in GCS is a copy
# that survives it.
#
# The bucket is <project_id>-sql-exports (Architect name default on #2), in Montréal, private, versioned.
# Every run writes the same object, so the previous night's export becomes a noncurrent version. The one
# lifecycle rule deletes objects older than 30 days, live or noncurrent, so about 30 nights are kept.
#
# The job runs at 05:15 America/Chicago, between the maintenance window (05:00 CT) and the backup
# (05:30 CT), and after dev's 04:45 CT start (#14). It POSTs the Cloud SQL Admin `export` API with an OAuth
# token minted for var.export_service_account_email. That service account is created locally, never here.
#
# Needs cloudscheduler.googleapis.com and storage.googleapis.com (modules/project).
#
# LOCAL FOLLOW-UP (L1(a), ef#885), IAM is never written in this public repo:
#   1. Create the scheduler service account (ops-scheduler) and grant it roles/cloudsql.viewer on the
#      project, which carries cloudsql.instances.export.
#   2. Grant the apply identity (tf-apply) roles/iam.serviceAccountUser on that one service account only:
#      creating a job that mints its token needs iam.serviceAccounts.actAs on it.
#   3. Grant the Cloud SQL instance's own service account (output instance_service_account_email)
#      roles/storage.objectAdmin on this bucket only. The export writes the object as that account, and
#      overwriting the previous night's object needs delete as well as create.
locals {
  export_bucket_name            = "${var.project_id}-sql-exports"
  export_object_uri             = "gs://${local.export_bucket_name}/${local.database_name}.sql.gz" # .gz: Cloud SQL compresses
  export_retention_days         = 30
  export_schedule               = "15 5 * * *"
  export_time_zone              = "America/Chicago"
  export_oauth_scope            = "https://www.googleapis.com/auth/cloud-platform"
  export_sqladmin_endpoint_base = "https://sqladmin.googleapis.com/v1"
}

resource "google_storage_bucket" "sql_exports" {
  project       = var.project_id
  name          = local.export_bucket_name
  location      = upper(var.region)
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # The point of this bucket is to outlive things: never empty it on destroy.
  force_destroy = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = local.export_retention_days
      # ANY: the rule applies to noncurrent versions too, so overwritten exports don't pile up.
      with_state = "ANY"
    }
  }
}

resource "google_cloud_scheduler_job" "sql_export" {
  project     = var.project_id
  region      = var.region
  name        = "${var.instance_name}-nightly-export"
  description = "Nightly export of the ${local.database_name} database to ${local.export_bucket_name} (ecofolk-infra#2)."

  schedule  = local.export_schedule
  time_zone = local.export_time_zone

  http_target {
    http_method = "POST"
    uri         = "${local.export_sqladmin_endpoint_base}/projects/${var.project_id}/instances/${google_sql_database_instance.postgres.name}/export"

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      exportContext = {
        fileType  = "SQL"
        uri       = local.export_object_uri
        databases = [local.database_name]
      }
    }))

    oauth_token {
      service_account_email = var.export_service_account_email
      scope                 = local.export_oauth_scope
    }
  }
}
