# alerts.tf — the three alerts that mean EcoFolk users are broken (ecofolk-infra#24, ef#406):
#   1. API 5xx rate      — Cloud Run's own request_count metric, no log filter needed;
#   2. DB connection failures — a log-based metric over var.db_connection_failure_log_filter;
#   3. media write failures   — a log-based metric over var.media_write_failure_log_filter. The spec
#      says "R2"; media moved to the GCS bucket in modules/media_bucket (#21 re-spec), so it is named
#      for what it watches, not the store;
#   4. stale SQL export     — an absence alert on a log-based metric over the nightly export job's Cloud
#      Scheduler execution log: no successful run (modules/cloudsql/export.tf) in about a day
#      (ecofolk-infra#109, #96);
#   5. failed SQL export attempt — a log-match alert on any non-2xx finish of that same job, so a refused
#      export pages the night it happens (ecofolk-infra#109 rework, Architect plan on #135).
#
# What is deliberately NOT here (Architect spec on #24):
#   - no google_monitoring_notification_channel: the channel is email (owner's ruling) and is made by
#     hand, so no address ever reaches this public repo. Policies reference channels by ID only;
#   - no log filter guessed from here: the app's log shapes are private, so both filters are inputs
#     with no default (L-ALERT supplies them);
#   - no IAM of any kind.
#
# Alert policies and log-based metrics are project-level, not regional: nothing here takes a region.
# Needs monitoring.googleapis.com and logging.googleapis.com, both on by default in a new project.
#
# LOCAL FOLLOW-UP (L-ALERT, ecofolk): the two log filters from the app's actual log fields (plus a
# structured log event where a failure isn't logged distinctly today), the hand-made email channel, its
# ID in repo variable ALERT_CHANNEL_IDS, and wiring this module into environments/dev.

locals {
  # #13: dev and prod keep their names (each owns its project); a namespace env (qa) gets -<env>.
  env_suffix = contains(["dev", "prod"], var.env) ? "" : "-${var.env}"

  # Every request to the API service, and the 5xx subset of it.
  api_requests_filter = join(" AND ", [
    "metric.type=\"run.googleapis.com/request_count\"",
    "resource.type=\"cloud_run_revision\"",
    "resource.label.service_name=\"${var.api_service_name}\"",
  ])
  api_5xx_filter = "${local.api_requests_filter} AND metric.label.response_code_class=\"5xx\""

  # 5xx window, ratio and floor (spec: over 5% of requests AND at least 10 requests in 10 min, so one
  # error at low traffic doesn't page).
  api_5xx_window      = "600s"
  api_5xx_ratio       = 0.05
  api_min_requests_gt = 9 # threshold conditions take GT/LT only: "> 9" is ">= 10" for a request count

  # Log-based failure alerts: any matching entry in a 5-minute window fires.
  log_failure_window = "300s"

  # Successful attempts of the nightly export job (#109, Architect ruling on #111). Cloud Scheduler's
  # execution log is on by default; Cloud SQL's export audit entry is DATA_READ (Data Access, off by
  # default), so it is deliberately not used. The job POSTs the Admin API's export method, so a successful
  # attempt means the job fired and the API accepted the request, not that the export finished.
  #   - Scheduler writes one entry when an attempt starts and one when it finishes; the finish entry's
  #     jsonPayload."@type" is google.cloud.scheduler.logging.AttemptFinished;
  #   - an HTTP target's attempt succeeds on a response code in [200, 299] (HttpTarget, Scheduler API).
  #     The finish entry's httpRequest.status carries that code (confirmed live: 200 on a success, 412 on
  #     failed attempts; #111 c6317181637). A range test only matches a present value, so an attempt with
  #     no response (token mint failure, deadline) can't match;
  #   - resource.type cloud_scheduler_job, labelled with the job's id: this job only.
  # The filter is a pure AND of these clauses, with no OR and no NOT: tests/monitoring.tftest.hcl checks
  # its structure, because one OR anywhere would let a failed attempt count as a success.
  sql_export_success_filter = join(" AND ", [
    "resource.type=\"cloud_scheduler_job\"",
    "resource.labels.job_id=\"${var.sql_export_job_name}\"",
    "jsonPayload.\"@type\"=\"type.googleapis.com/google.cloud.scheduler.logging.AttemptFinished\"",
    "httpRequest.status>=200",
    "httpRequest.status<300",
  ])

  # Failed attempts of the same job (#109 rework). The success metric is sparse (one point a night, and
  # none on a failing night), so an absence condition on it never armed; a log-match condition fires on
  # the failure entry itself. Same three clauses as the success filter's scope, with the status clause
  # negated: NOT (2xx) also matches a finish entry with no httpRequest.status (a token mint failure or a
  # deadline), which a "status>=300" range test would miss. A pure AND of three clauses; the last is the
  # one NOT. tests/monitoring.tftest.hcl checks it, with known-wrongs for a 2xx-only filter and a missing
  # job id.
  sql_export_failure_filter = join(" AND ", [
    "resource.type=\"cloud_scheduler_job\"",
    "resource.labels.job_id=\"${var.sql_export_job_name}\"",
    "jsonPayload.\"@type\"=\"type.googleapis.com/google.cloud.scheduler.logging.AttemptFinished\"",
    "NOT (httpRequest.status>=200 AND httpRequest.status<300)",
  ])

  # The job runs every 24 h. The API caps a metric-absence HORIZON, duration + alignment period
  # combined, at 25 h (an API-side check CI can't see: #111's first apply 400'd on 29.5 h), and the
  # ruled 48 h isn't possible. The horizon must also exceed 24 h, or the alert pages every morning just
  # before the next run. So 19 h + 6 h = 25 h: the 6 h alignment window keeps a night's success visible
  # for 6 h after it lands, and the alert fires about 25 h after the last success, around 11:15Z the
  # morning after a missed 10:15Z export. The policy's precondition enforces 24 h < horizon <= 25 h.
  sql_export_absence_duration = "${var.sql_export_absence_duration_seconds}s" # 19 h
  sql_export_alignment_period = "${var.sql_export_alignment_period_seconds}s" # 6 h
}

# 1. API 5xx rate. Two conditions, combined with AND: both must hold over the same 10-minute window.
resource "google_monitoring_alert_policy" "api_5xx_rate" {
  project               = var.project_id
  display_name          = "EcoFolk API: 5xx rate over 5%"
  user_labels           = { env = var.env }
  combiner              = "AND"
  notification_channels = var.notification_channels

  conditions {
    display_name = "5xx responses are over 5% of requests (10 min)"

    condition_threshold {
      filter          = local.api_5xx_filter
      comparison      = "COMPARISON_GT"
      threshold_value = local.api_5xx_ratio
      duration        = "0s"

      aggregations {
        alignment_period     = local.api_5xx_window
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.service_name"]
      }

      denominator_filter = local.api_requests_filter

      denominator_aggregations {
        alignment_period     = local.api_5xx_window
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.service_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  conditions {
    display_name = "At least 10 requests (10 min)"

    condition_threshold {
      filter          = local.api_requests_filter
      comparison      = "COMPARISON_GT"
      threshold_value = local.api_min_requests_gt
      duration        = "0s"

      aggregations {
        alignment_period     = local.api_5xx_window
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.service_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      **What broke:** more than 5% of requests to the EcoFolk API (Cloud Run service `${var.api_service_name}`) returned a 5xx in the last 10 minutes, with at least 10 requests in that window. Users are seeing errors.

      **First thing to check:** Cloud Run → `${var.api_service_name}` → Logs, filtered to severity ERROR, for the failing route and stack trace. Then check whether a new revision went out just before the alert (Revisions tab); if so, route traffic back to the previous revision.
    EOT
  }
}

# 2. DB connection failures.
resource "google_logging_metric" "db_connection_failures" {
  project     = var.project_id
  name        = "ecofolk-db-connection-failures${local.env_suffix}"
  description = "API log entries for a failed database connection attempt (ecofolk-infra#24). Filter supplied by L-ALERT."
  filter      = var.db_connection_failure_log_filter

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "db_connection_failures" {
  project               = var.project_id
  display_name          = "EcoFolk API: database connection failures"
  user_labels           = { env = var.env }
  combiner              = "OR"
  notification_channels = var.notification_channels

  conditions {
    display_name = "Any database connection failure (5 min)"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.db_connection_failures.name}\" AND resource.type=\"cloud_run_revision\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period     = local.log_failure_window
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      **What broke:** the EcoFolk API logged at least one failed database connection in the last 5 minutes. Requests that need the database are failing.

      **First thing to check:** Cloud SQL → the instance's Overview: is it RUNNING (not stopped, restarting or in maintenance)? Then its connection count against the limit, then the API's logs for the connection error text (refused, timeout, or auth).

      **Scheduler invariant (ef#894):** this alert cannot be time-scoped in a log filter, so every DB-touching Cloud Scheduler job must be `time_zone` America/Chicago with no run inside the 22:15–04:45 CT dev SQL stop. A job that runs in that window pages here. See docs/alerting-policy.md.
    EOT
  }
}

# 3. Media write failures.
resource "google_logging_metric" "media_write_failures" {
  project     = var.project_id
  name        = "ecofolk-media-write-failures${local.env_suffix}"
  description = "API log entries for a failed media upload/write to the media bucket (ecofolk-infra#24). Filter supplied by L-ALERT."
  filter      = var.media_write_failure_log_filter

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "media_write_failures" {
  project               = var.project_id
  display_name          = "EcoFolk API: media write failures"
  user_labels           = { env = var.env }
  combiner              = "OR"
  notification_channels = var.notification_channels

  conditions {
    display_name = "Any media write failure (5 min)"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.media_write_failures.name}\" AND resource.type=\"cloud_run_revision\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period     = local.log_failure_window
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      **What broke:** the EcoFolk API failed to write at least one media file (photo or audio upload) to the media bucket in the last 5 minutes. Users' uploads are being lost.

      **First thing to check:** the API's logs for the storage error code. A 403 means the runtime service account lost its role on the bucket; a 404 means the bucket name the API is configured with is wrong; 5xx or timeouts mean a Cloud Storage incident (check the Google Cloud status page).
    EOT
  }
}

# 4. Stale SQL export (#109, #96 option 2). #100 keeps the last good export when the nightly job fails;
# this makes the failure visible. It is a threshold on the success count (< 1 per window) with missing data
# treated as a violation: the first version used condition_absent, which Monitoring never fired on this
# sparse log-based metric (one point in 6 failed nights, 2026-10-21 to 10-27). This policy covers "the job
# stopped firing at all"; policy 5 covers an attempt that fired and failed.
resource "google_logging_metric" "sql_export_successes" {
  project     = var.project_id
  name        = "ecofolk-sql-export-successes${local.env_suffix}"
  description = "Successful (2xx) attempts of the nightly Cloud SQL export's Cloud Scheduler job, from its execution log (ecofolk-infra#109)."
  filter      = local.sql_export_success_filter

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "sql_export_stale" {
  project               = var.project_id
  display_name          = "EcoFolk database: nightly export job has not succeeded"
  combiner              = "OR"
  notification_channels = var.notification_channels
  user_labels           = { env = var.env }

  lifecycle {
    precondition {
      condition = (
        var.sql_export_absence_duration_seconds + var.sql_export_alignment_period_seconds > 86400 &&
        var.sql_export_absence_duration_seconds + var.sql_export_alignment_period_seconds <= 90000
      )
      error_message = "the stale-export horizon (absence duration + alignment period) must be over 24 h, or it pages every morning before the next daily run, and at most 25 h, the Monitoring API's cap on the two combined."
    }
  }

  conditions {
    display_name = "Fewer than 1 successful nightly export job run (about 25 h)"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.sql_export_successes.name}\" AND resource.type=\"cloud_scheduler_job\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = local.sql_export_absence_duration

      # No data at all is a violation: a metric with no points is exactly the failure this catches.
      evaluation_missing_data = "EVALUATION_MISSING_DATA_ACTIVE"

      aggregations {
        alignment_period     = local.sql_export_alignment_period
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      **What broke:** the Cloud Scheduler job `${var.sql_export_job_name}` has not had a successful run for about a day. Its nightly 05:15 CT export of the Cloud SQL instance `${var.sql_instance_name}` has failed or stopped running. The stored exports are safe (#96), but the newest one is getting old: a restore now loses everything since it.

      **What a successful run proves, and what it does not:** a success means the job fired **and the Cloud SQL Admin API accepted the export request** (a 2xx response). It does **not** prove the export then completed: the export runs asynchronously after that. Completion is checked by runbook §3.2 step 1 (`gcloud sql operations list … --filter="operationType=EXPORT"`). So this alert catches the job not firing, being paused or deleted, a permission regression, or the API rejecting the request; it can stay quiet while accepted exports fail later.

      **First thing to check:** Cloud Scheduler → `${var.sql_export_job_name}` → View logs: did it run, and what status did it get back (a 403 is a permission regression on the scheduler's service account; a 412 FAILED_PRECONDITION with no EXPORT operation created was the instance's service account missing objectCreator on the bucket, #135)? Then Cloud SQL → `${var.sql_instance_name}` → Operations, for the last EXPORT and its error. Then the bucket `${var.project_id}-sql-exports`: the live object's updated time is the last good export.

      **Runbook:** [§3, Restore from the nightly export](https://github.com/rosebud785/ecofolk-infra/blob/main/docs/runbook.md#3-restore-from-the-nightly-export); §3.2 step 1 confirms whether an export completed.
    EOT
  }
}

# 5. Failed SQL export attempt (#109 rework). Fires on the first non-2xx finish of the export job, from
# the Scheduler execution log: a refused export (the 412s from 2026-10-22, #135) pages the same night.
# A log-match condition must be the only condition in its policy and needs a notification rate limit;
# the incident closes itself so the next night's failure opens a new one.
resource "google_monitoring_alert_policy" "sql_export_attempt_failed" {
  project               = var.project_id
  display_name          = "EcoFolk database: nightly export attempt failed"
  combiner              = "OR"
  notification_channels = var.notification_channels
  user_labels           = { env = var.env }

  conditions {
    display_name = "Export job attempt finished with a non-2xx status"

    condition_matched_log {
      filter = local.sql_export_failure_filter
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "3600s"
    }
    auto_close = "86400s"
  }

  documentation {
    mime_type = "text/markdown"
    content   = <<-EOT
      **What broke:** an attempt of the Cloud Scheduler job `${var.sql_export_job_name}` finished with a non-2xx response (or none). Its nightly 05:15 CT export of the Cloud SQL instance `${var.sql_instance_name}` was refused or not sent, so tonight's export did not happen. The stored exports are safe (#96), but the newest one is now a day older.

      **First thing to check:** Cloud Scheduler → `${var.sql_export_job_name}` → View logs, for the status of the attempt. A 403 is a permission regression on the scheduler's service account; a 412 FAILED_PRECONDITION with no EXPORT operation created is the Cloud SQL instance's service account lacking `roles/storage.objectAdmin` on the bucket `${var.project_id}-sql-exports` (overwriting the fixed-name object needs delete as well as create; #135). Then Cloud SQL → `${var.sql_instance_name}` → Operations, for the last EXPORT and its error.

      **Related alert:** "nightly export job has not succeeded" is the companion that fires when the job stops running at all, or when no success has landed in about a day.

      **Runbook:** [§3, Restore from the nightly export](https://github.com/rosebud785/ecofolk-infra/blob/main/docs/runbook.md#3-restore-from-the-nightly-export); §3.2 step 1 confirms whether an export completed.
    EOT
  }
}
