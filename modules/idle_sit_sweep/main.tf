# main.tf — Cloud Scheduler job for the idle-sit sweep, Terraform half (ecofolk-infra#17, cloud part of
# ecofolk#460; Architect's OIDC redesign on PR #86, 2026-10-18).
#
# One job POSTs {api_url}/internal/sweep-idle-sits on var.sweep_schedule (America/Chicago). The default,
# every 2 hours, stays under the API's 3h idle threshold. environments/dev passes 0 5-21/2 * * *, so no
# sweep runs while #14 has dev Cloud SQL stopped (22:15–04:45 CT); otherwise each overnight sweep is a DB
# connection failure that #24's alert pages on.
#
# The job proves who it is with a Google-signed OIDC ID token minted for var.invoker_sa_email, with the
# audience set to the endpoint URL. The API verifies that token (ecofolk#1092): audience, email and
# email_verified. There is no static secret: nothing to store, rotate or leak into state, and no header
# is set in Terraform or out of band. Terraform owns the whole job, so there is no ignore_changes.
#
# Needs cloudscheduler.googleapis.com (modules/project). No IAM here: the invoker SA is created locally.
#
# LOCAL FOLLOW-UP (ecofolk#460 / L1(a)), IAM is never written in this public repo:
#   1. Create service account sweep-invoker in the project, with no roles.
#   2. Confirm the identity that applies this job (tf-apply) can actAs sweep-invoker
#      (iam.serviceAccounts.actAs, e.g. roles/iam.serviceAccountUser on that SA only).
#   3. Add the ef#395 inventory line.
locals {
  name      = "idle-sit-sweep"
  time_zone = "America/Chicago"
  path      = "/internal/sweep-idle-sits"
  endpoint  = "${var.api_url}${local.path}"
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
    uri         = local.endpoint

    oidc_token {
      service_account_email = var.invoker_sa_email
      audience              = local.endpoint
    }
  }
}
