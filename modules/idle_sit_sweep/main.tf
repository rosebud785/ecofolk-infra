# main.tf — Cloud Scheduler job for the idle-sit sweep, Terraform half (ecofolk-infra#17, cloud part of
# ecofolk#460; Architect respec 2026-10-16, amended the same day).
#
# One job POSTs {api_url}/internal/sweep-idle-sits on var.sweep_schedule (America/Chicago). The default,
# every 2 hours, stays under the API's 3h idle threshold. environments/dev passes 0 5-21/2 * * *, so no
# sweep runs while #14 has dev Cloud SQL stopped (22:15–04:45 CT); otherwise each overnight sweep is a DB
# connection failure that #24's alert pages on.
#
# No oidc_token and no oauth_token: the API reads its sweep credential from the same request header a
# Scheduler token would write, so the two would collide and the sweep would 401. The API service is public
# (it serves the web client), so a Google-signed token adds nothing.
#
# No header value here. Scheduler stores http_target headers as literals and can't resolve a Secret
# Manager reference at call time, so writing the value in Terraform would put it in state (and C7 forbids
# google_secret_manager_secret_version). The header is set out of band after the first apply (README.md);
# ignore_changes keeps every later apply from removing it.
#
# Needs cloudscheduler.googleapis.com (modules/project). No service account and no IAM: the job carries no
# Google token.
#
# LOCAL FOLLOW-UP (ecofolk#460 / L1(a)): after the first apply, set the header with
# `gcloud scheduler jobs update http` (value piped from 1Password, never echoed; README.md), and add the
# ef#395 inventory line.
locals {
  name      = "idle-sit-sweep"
  time_zone = "America/Chicago"
  path      = "/internal/sweep-idle-sits"
}

resource "google_cloud_scheduler_job" "sweep" {
  project     = var.project_id
  region      = var.region
  name        = local.name
  description = "POSTs ${local.path} on the API to close idle sits (ecofolk-infra#17, ecofolk#460)."

  schedule  = var.sweep_schedule
  time_zone = local.time_zone

  http_target {
    http_method = "POST"
    uri         = "${var.api_url}${local.path}"
  }

  lifecycle {
    # The request header is set out of band (README.md); Terraform never writes or removes it.
    ignore_changes = [http_target[0].headers]
  }
}
