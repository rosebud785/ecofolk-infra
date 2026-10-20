# main.tf — dev Cloud SQL off-hours stop and start (ecofolk-infra#14, C14; Architect SPEC OK 2026-10-16
# with amendment).
#
# Why: a Cloud SQL instance bills while idle. Two Cloud Scheduler jobs PATCH the instance's
# settings.activationPolicy through the Cloud SQL Admin API: NEVER at 22:15 CT (stopped), ALWAYS at
# 04:45 CT (running). Ops hours are 07:00–22:00 CT.
#
# INVARIANT (ef#894, docs/alerting-policy.md): the 22:15-04:45 CT stop window is the reason every
# DB-touching Cloud Scheduler job must be time_zone America/Chicago with no run inside it. The DB
# connection failure alert (modules/monitoring) cannot be time-scoped in a log filter, so a run in the
# window is a false page.
#
# Dev only. environments/dev is the only caller, and var.project_id refuses a *-prod project, so a prod
# composition (#12) that instantiates this module fails at plan. Stopping dev also stops the QA namespace
# (#13 shares the instance); that is intended.
#
# The jobs' OAuth token is minted for var.service_account_email (ops-scheduler, the same account as #2's
# export job). That account is created locally, never here.
#
# modules/cloudsql ignores settings.activation_policy, so an apply from main while dev is stopped does
# not start it again.
#
# Needs cloudscheduler.googleapis.com and sqladmin.googleapis.com (modules/project).
#
# LOCAL FOLLOW-UP (L1(a), ef#885), IAM is never written in this public repo:
#   1. Grant ops-scheduler (created for #2) roles/cloudsql.editor on ecofolk-dev only, never on prod. It
#      carries cloudsql.instances.update, which the PATCH needs.
#   2. tf-apply's roles/iam.serviceAccountUser on ops-scheduler (#2's item 2) also covers these jobs.
locals {
  # #13: dev and prod keep their names (each owns its project); a namespace env (qa) gets -<env>.
  env_suffix = contains(["dev", "prod"], var.env) ? "" : "-${var.env}"

  time_zone = "America/Chicago"

  stop_schedule = "15 22 * * *"

  # The ONE place the start time lives (Architect amendment on #14). It must precede #2's 05:00 CT
  # maintenance window (modules/cloudsql/main.tf), the 05:15 CT export and the 05:30 CT backup: Cloud SQL
  # skips the automated backup of a stopped instance, and the Admin `export` call fails against one.
  start_schedule = "45 4 * * *"

  sqladmin_instance_uri = "https://sqladmin.googleapis.com/v1/projects/${var.project_id}/instances/${var.instance_name}"
  oauth_scope           = "https://www.googleapis.com/auth/cloud-platform"

  jobs = {
    stop = {
      schedule          = local.stop_schedule
      activation_policy = "NEVER"
      description       = "Stops Cloud SQL instance ${var.instance_name} out of ops hours, 22:15 CT (ecofolk-infra#14)."
    }
    start = {
      schedule          = local.start_schedule
      activation_policy = "ALWAYS"
      description       = "Starts Cloud SQL instance ${var.instance_name} at 04:45 CT, before the 05:00 maintenance window (ecofolk-infra#14)."
    }
  }
}

resource "google_cloud_scheduler_job" "this" {
  for_each = var.enable_off_hours ? local.jobs : {}

  project     = var.project_id
  region      = var.region
  name        = "${var.instance_name}-off-hours-${each.key}${local.env_suffix}"
  description = each.value.description

  schedule  = each.value.schedule
  time_zone = local.time_zone

  http_target {
    http_method = "PATCH"
    uri         = local.sqladmin_instance_uri

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      settings = {
        activationPolicy = each.value.activation_policy
      }
    }))

    oauth_token {
      service_account_email = var.service_account_email
      scope                 = local.oauth_scope
    }
  }
}
