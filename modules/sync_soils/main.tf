# main.tf — Cloud Scheduler job for sync-soils (ecofolk-infra#174; Architect's routing on #174 / ecofolk#1220).
#
# The app's registry (ecofolk routes/internal.ts) gives sync-soils the cadence monthly, the 2nd at 06:00, America/Chicago,
# and no environment scheduled it, so nothing ever synced it live. One job POSTs {api_url}/internal/sync-soils on
# that cadence, outside #14's 22:15–04:45 CT dev Cloud SQL stop (docs/alerting-policy.md). The schedule is fixed
# here, not a variable: it must match the app's table.
#
# Copy of the modules/sync_usgs_water pattern: a Google-signed OIDC ID token minted for var.invoker_sa_email,
# audience = the endpoint URL, no static secret and no header. The invoker is the EXISTING sweep invoker SA,
# passed in; nothing here creates a service account, a binding or an actAs grant.
#
# Needs cloudscheduler.googleapis.com (modules/project). No IAM here.
locals {
  # #13: dev and prod keep their names (each owns its project); a namespace env (qa) gets -<env>.
  env_suffix = contains(["dev", "prod"], var.env) ? "" : "-${var.env}"

  name      = "sync-soils"
  time_zone = "America/Chicago"
  schedule  = "0 6 2 * *"
  path      = "/internal/sync-soils"
  endpoint  = "${var.api_url}${local.path}"
}

resource "google_cloud_scheduler_job" "sync" {
  project     = var.project_id
  region      = var.region
  name        = "${local.name}${local.env_suffix}"
  description = "POSTs ${local.path} on the API to sync USDA SSURGO soil map units (ecofolk-infra#174)."

  schedule  = local.schedule
  time_zone = local.time_zone

  http_target {
    http_method = "POST"
    uri         = local.endpoint

    oidc_token {
      service_account_email = var.invoker_sa_email
      audience              = local.endpoint
    }
  }
}
