# alerts.tf — the three alerts that mean EcoFolk users are broken (ecofolk-infra#24, ef#406):
#   1. API 5xx rate      — Cloud Run's own request_count metric, no log filter needed;
#   2. DB connection failures — a log-based metric over var.db_connection_failure_log_filter;
#   3. media write failures   — a log-based metric over var.media_write_failure_log_filter. The spec
#      says "R2"; media moved to the GCS bucket in modules/media_bucket (#21 re-spec), so it is named
#      for what it watches, not the store;
#   4. stale SQL export     — an absence alert on a log-based metric over the Cloud SQL audit log: no
#      successful nightly export (modules/cloudsql/export.tf) in about a day (ecofolk-infra#109, #96).
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

  # Successful completion of a Cloud SQL export on this module's instance (#109). Field names checked
  # against Google's docs and API protos, cited on the PR:
  #   - Cloud SQL's audit-logging page lists cloudsql.instances.export (LRO) under DATA_READ, which
  #     writes the Data Access log, not Admin Activity as the spec assumed. Both log names are matched so
  #     the filter is right either way; Data Access logs are off by default (see the LOCAL FOLLOW-UP);
  #   - an LRO writes one entry at the start and one at completion; the completion entry carries
  #     operation.last=true (Understanding audit logs);
  #   - protoPayload.status is the operation's google.rpc.Status: no code, or code 0, is success.
  # UNVERIFIED until the first dev apply plus the next morning's export: no real entry has been read.
  sql_export_success_filter = join(" AND ", [
    "(logName:\"cloudaudit.googleapis.com%2Factivity\" OR logName:\"cloudaudit.googleapis.com%2Fdata_access\")",
    "protoPayload.serviceName=\"cloudsql.googleapis.com\"",
    "protoPayload.methodName=\"cloudsql.instances.export\"",
    "operation.last=true",
    "(NOT protoPayload.status.code:* OR protoPayload.status.code=0)",
    "resource.type=\"cloudsql_database\"",
    "resource.labels.database_id=\"${var.project_id}:${var.sql_instance_name}\"",
  ])

  # The export runs every 24 h, but a metric-absence duration can be at most 23.5 h (the API's maximum;
  # the spec's 48 h isn't possible). On its own that would page every morning just before the next run.
  # A 6 h alignment window keeps the night's success visible for 6 h after it lands, so the alert fires
  # about 29.5 h after the last success: around 10:45 CT the morning after a missed export.
  sql_export_absence_duration = "84600s" # 23.5 h, the maximum
  sql_export_alignment_period = "21600s" # 6 h; alerting allows up to 25 h
}

# 1. API 5xx rate. Two conditions, combined with AND: both must hold over the same 10-minute window.
resource "google_monitoring_alert_policy" "api_5xx_rate" {
  project               = var.project_id
  display_name          = "EcoFolk API: 5xx rate over 5%"
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
  name        = "ecofolk-db-connection-failures"
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
  name        = "ecofolk-media-write-failures"
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
# this makes the failure visible. Absence conditions only arm once the metric has written a point, so the
# alert is quiet until the first successful export the metric sees.
#
# LOCAL FOLLOW-UP (never IAM in this public repo): if Cloud SQL's export entry is in the Data Access log,
# as its audit-logging page says, turn on Data Access audit logs (DATA_READ) for cloudsql.googleapis.com
# in the project. Until then the metric sees nothing and this alert never arms.
resource "google_logging_metric" "sql_export_successes" {
  project     = var.project_id
  name        = "ecofolk-sql-export-successes"
  description = "Completed, error-free Cloud SQL exports of the module's instance, from the audit log (ecofolk-infra#109)."
  filter      = local.sql_export_success_filter

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "sql_export_stale" {
  project               = var.project_id
  display_name          = "EcoFolk database: no successful nightly export"
  combiner              = "OR"
  notification_channels = var.notification_channels

  conditions {
    display_name = "No successful Cloud SQL export (about 29.5 h)"

    condition_absent {
      filter   = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.sql_export_successes.name}\" AND resource.type=\"cloudsql_database\""
      duration = local.sql_export_absence_duration

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
      **What broke:** no export of the Cloud SQL instance `${var.sql_instance_name}` has completed without error for about a day. The nightly export (05:15 CT) has failed or stopped running. The stored exports are safe (#96), but the newest one is getting old: a restore now loses everything since it.

      **First thing to check:** Cloud SQL → `${var.sql_instance_name}` → Operations, for the last export and its error. Then Cloud Scheduler → `${var.sql_instance_name}-nightly-export`: did it run, and what status did it get back? Then the bucket `${var.project_id}-sql-exports`: the live object's updated time is the last good export.

      **Runbook:** [§3, Restore from the nightly export](https://github.com/rosebud785/ecofolk-infra/blob/main/docs/runbook.md#3-restore-from-the-nightly-export).
    EOT
  }
}
