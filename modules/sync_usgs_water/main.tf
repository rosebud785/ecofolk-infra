# main.tf — Cloud Scheduler job for sync-usgs-water (ecofolk-infra#98; Architect's ruling on #97 / ef#894
# and cloud spec on #98, 2026-10-19).
#
# The app's table (ecofolk routes/internal.ts, ef PR #1105) moved sync-usgs-water to 0 5,11,17 * * *
# America/Chicago, but nothing fires it live until this job exists. One job POSTs
# {api_url}/internal/sync-usgs-water at 05:00, 11:00 and 17:00 CT, all outside #14's 22:15–04:45 CT dev
# Cloud SQL stop (docs/alerting-policy.md). The schedule is fixed here, not a variable: it must match the
# app's table, and every hour it fires in is outside the stop in any environment.
#
# Same pattern as modules/idle_sit_sweep: a Google-signed OIDC ID token minted for var.invoker_sa_email,
# audience = the endpoint URL, no static secret and no header. The invoker is the EXISTING sweep invoker
# SA, passed in; nothing here creates a service account, a binding or an actAs grant.
#
# Needs cloudscheduler.googleapis.com (modules/project). No IAM here.
#
# LOCAL FOLLOW-UP (ecofolk#1092, app side): the API's verifier checks the token's email against its
# configured invoker SA. Confirm /internal/sync-usgs-water accepts the sweep invoker's email and this
# audience; if it doesn't, fix it in the app, not with IAM here.
locals {
  # #13: dev and prod keep their names (each owns its project); a namespace env (qa) gets -<env>.
  env_suffix = contains(["dev", "prod"], var.env) ? "" : "-${var.env}"

  name      = "sync-usgs-water"
  time_zone = "America/Chicago"
  schedule  = "0 5,11,17 * * *"
  path      = "/internal/sync-usgs-water"
  endpoint  = "${var.api_url}${local.path}"
}

resource "google_cloud_scheduler_job" "sync" {
  project     = var.project_id
  region      = var.region
  name        = "${local.name}${local.env_suffix}"
  description = "POSTs ${local.path} on the API to sync USGS water data (ecofolk-infra#98, ef PR #1105)."

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
