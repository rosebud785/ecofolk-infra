# alerts.tf — the three alerts that mean EcoFolk users are broken (ecofolk-infra#24, ef#406):
#   1. API 5xx rate      — Cloud Run's own request_count metric, no log filter needed;
#   2. DB connection failures — a log-based metric over var.db_connection_failure_log_filter;
#   3. media write failures   — a log-based metric over var.media_write_failure_log_filter. The spec
#      says "R2"; media moved to the GCS bucket in modules/media_bucket (#21 re-spec), so it is named
#      for what it watches, not the store.
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
