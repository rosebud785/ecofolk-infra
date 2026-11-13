# main.tf — Cloud Scheduler job for sync-health (ecofolk-infra#156; ecofolk#1349).
#
# The app's sync-health job (ecofolk routes/internal.ts, ingest/syncHealth.ts) checks every watched source's last
# successful sync against its cadence and logs one `sync_health_failed {job, reason}` warn line per problem; the
# alert on that line is in modules/monitoring. Nothing fires the job until this exists. One job POSTs
# {api_url}/internal/sync-health daily at 07:15 America/Chicago, the app's own registry cadence (routes/internal.ts: "15 7 * * *, after the other syncs"): after the last scheduled sync (iNat 05:30, usgs 05/11/17 and the two monthly jobs at 06:00 on the 1st and 2nd), and outside #14's
# 22:15–04:45 CT dev Cloud SQL stop (docs/alerting-policy.md), since the job reads the database. The schedule is
# fixed here, not a variable.
#
# Same pattern as modules/sync_usgs_water: a Google-signed OIDC ID token minted for var.invoker_sa_email,
# audience = the endpoint URL, no static secret and no header. The invoker is the EXISTING sweep invoker SA,
# passed in; nothing here creates a service account, a binding or an actAs grant.
#
# Needs cloudscheduler.googleapis.com (modules/project). No IAM here.
#
# LOCAL FOLLOW-UP (ecofolk app side): the API's verifier checks the token's email against its configured
# invoker SA. Confirm /internal/sync-health accepts the sweep invoker's email and this audience; if it
# doesn't, fix it in the app, not with IAM here.
locals {
  # #13: dev and prod keep their names (each owns its project); a namespace env (qa) gets -<env>.
  env_suffix = contains(["dev", "prod"], var.env) ? "" : "-${var.env}"

  name      = "sync-health"
  time_zone = "America/Chicago"
  schedule  = "15 7 * * *"
  path      = "/internal/sync-health"
  endpoint  = "${var.api_url}${local.path}"
}

resource "google_cloud_scheduler_job" "sync" {
  project     = var.project_id
  region      = var.region
  name        = "${local.name}${local.env_suffix}"
  description = "POSTs ${local.path} on the API to check that every watched sync is still running (ecofolk-infra#156, ecofolk#1349)."

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
