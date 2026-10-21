# Issue #24 AC: with a mock provider (no credentials, no GCP), assert the three policies exist, the 5xx
# policy has both the ratio and the minimum-count clauses (ANDed), the log-filter and channel variables
# have no defaults, no google_monitoring_notification_channel exists, no IAM, and no email-shaped string
# appears anywhere in modules/monitoring/** (the channel is email; its address never lands here).
mock_provider "google" {}

variables {
  project_id                       = "ecofolk-dev"
  env                              = "dev"
  notification_channels            = ["projects/ecofolk-dev/notificationChannels/1234567890"]
  db_connection_failure_log_filter = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.db_connect_failed\""
  media_write_failure_log_filter   = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.media_write_failed\""
  api_host                         = "api.example.test"
  web_host                         = "web.example.test"
  sql_export_job_name              = "ecofolk-pg-nightly-export"
}

run "policies_exist_and_notify_the_channels" {
  command = plan

  assert {
    condition = alltrue([
      for p in [
        google_monitoring_alert_policy.api_5xx_rate,
        google_monitoring_alert_policy.db_connection_failures,
        google_monitoring_alert_policy.media_write_failures,
        google_monitoring_alert_policy.sql_export_stale,
      ] : p.project == "ecofolk-dev" && p.notification_channels == var.notification_channels
    ])
    error_message = "all four alert policies must exist on var.project_id and notify exactly var.notification_channels"
  }

  assert {
    condition = alltrue([
      for p in [
        google_monitoring_alert_policy.api_5xx_rate,
        google_monitoring_alert_policy.db_connection_failures,
        google_monitoring_alert_policy.media_write_failures,
        google_monitoring_alert_policy.sql_export_stale,
      ] : length(p.documentation) == 1 && length(trimspace(p.documentation[0].content)) > 0 && strcontains(p.documentation[0].content, "What broke") && strcontains(p.documentation[0].content, "First thing to check")
    ])
    error_message = "every policy must carry documentation.content saying what broke and the first thing to check"
  }
}

run "api_5xx_has_the_ratio_and_the_minimum_count_clauses" {
  command = plan

  assert {
    condition     = google_monitoring_alert_policy.api_5xx_rate.combiner == "AND" && length(google_monitoring_alert_policy.api_5xx_rate.conditions) == 2
    error_message = "the 5xx policy must AND exactly two conditions: the ratio and the minimum count"
  }

  # Ratio clause: 5xx request_count over all request_count for the service, > 5%, over 10 minutes.
  assert {
    condition = anytrue([
      for c in google_monitoring_alert_policy.api_5xx_rate.conditions : (
        strcontains(c.condition_threshold[0].filter, "metric.type=\"run.googleapis.com/request_count\"") &&
        strcontains(c.condition_threshold[0].filter, "metric.label.response_code_class=\"5xx\"") &&
        strcontains(c.condition_threshold[0].filter, "resource.label.service_name=\"ecofolk-api\"") &&
        strcontains(c.condition_threshold[0].denominator_filter, "metric.type=\"run.googleapis.com/request_count\"") &&
        strcontains(c.condition_threshold[0].denominator_filter, "resource.label.service_name=\"ecofolk-api\"") &&
        !strcontains(c.condition_threshold[0].denominator_filter, "response_code_class") &&
        c.condition_threshold[0].comparison == "COMPARISON_GT" &&
        c.condition_threshold[0].threshold_value == 0.05 &&
        c.condition_threshold[0].aggregations[0].alignment_period == "600s" &&
        c.condition_threshold[0].denominator_aggregations[0].alignment_period == "600s"
      )
    ])
    error_message = "the 5xx policy needs a ratio condition: 5xx request_count / all request_count for the API > 0.05 over 600s"
  }

  # Minimum-count clause: all requests for the service, > 9 (i.e. at least 10) over the same 10 minutes.
  assert {
    condition = anytrue([
      for c in google_monitoring_alert_policy.api_5xx_rate.conditions : (
        strcontains(c.condition_threshold[0].filter, "metric.type=\"run.googleapis.com/request_count\"") &&
        strcontains(c.condition_threshold[0].filter, "resource.label.service_name=\"ecofolk-api\"") &&
        !strcontains(c.condition_threshold[0].filter, "response_code_class") &&
        c.condition_threshold[0].denominator_filter == null &&
        c.condition_threshold[0].comparison == "COMPARISON_GT" &&
        c.condition_threshold[0].threshold_value == 9 &&
        c.condition_threshold[0].aggregations[0].alignment_period == "600s" &&
        c.condition_threshold[0].aggregations[0].per_series_aligner == "ALIGN_SUM"
      )
    ])
    error_message = "the 5xx policy needs a minimum-count condition: all requests for the API > 9 (at least 10) over 600s"
  }
}

run "api_service_name_follows_the_variable" {
  command = plan

  variables {
    api_service_name = "ecofolk-api-canary"
  }

  assert {
    condition = alltrue([
      for c in google_monitoring_alert_policy.api_5xx_rate.conditions :
      strcontains(c.condition_threshold[0].filter, "resource.label.service_name=\"ecofolk-api-canary\"")
    ])
    error_message = "the 5xx filters must take the service name from var.api_service_name"
  }
}

run "log_metrics_use_the_filters_passed_in" {
  command = plan

  assert {
    condition     = google_logging_metric.db_connection_failures.filter == var.db_connection_failure_log_filter
    error_message = "the DB connection failure metric must use var.db_connection_failure_log_filter verbatim"
  }

  assert {
    condition     = google_logging_metric.media_write_failures.filter == var.media_write_failure_log_filter
    error_message = "the media write failure metric must use var.media_write_failure_log_filter verbatim"
  }

  assert {
    condition = alltrue([
      for m in [google_logging_metric.db_connection_failures, google_logging_metric.media_write_failures] :
      m.project == "ecofolk-dev" && m.metric_descriptor[0].metric_kind == "DELTA" && m.metric_descriptor[0].value_type == "INT64"
    ])
    error_message = "log-based metrics must be DELTA/INT64 counters on var.project_id"
  }
}

run "log_policies_fire_on_any_matching_entry" {
  command = plan

  assert {
    condition = (
      google_monitoring_alert_policy.db_connection_failures.conditions[0].condition_threshold[0].filter ==
      "metric.type=\"logging.googleapis.com/user/ecofolk-db-connection-failures\" AND resource.type=\"cloud_run_revision\""
    )
    error_message = "the DB policy must watch the ecofolk-db-connection-failures log-based metric"
  }

  assert {
    condition = (
      google_monitoring_alert_policy.media_write_failures.conditions[0].condition_threshold[0].filter ==
      "metric.type=\"logging.googleapis.com/user/ecofolk-media-write-failures\" AND resource.type=\"cloud_run_revision\""
    )
    error_message = "the media policy must watch the ecofolk-media-write-failures log-based metric"
  }

  assert {
    condition = alltrue([
      for p in [google_monitoring_alert_policy.db_connection_failures, google_monitoring_alert_policy.media_write_failures] :
      p.conditions[0].condition_threshold[0].comparison == "COMPARISON_GT" && p.conditions[0].condition_threshold[0].threshold_value == 0
    ])
    error_message = "the log-based policies must fire on any failure (> 0)"
  }
}

# Spec item 4 and the amendment: no default on the two log filters or on the channels, so an unset value
# fails the apply. #109: nor on the export job's id, which must come from modules/cloudsql's output. A default isn't visible in a plan, so read variables.tf: each block (the text from
# `variable "<name>"` up to the next `variable "`) must exist and must have no `default =` line.
run "filter_and_channel_variables_have_no_default" {
  command = plan

  assert {
    condition = alltrue([
      for name in ["db_connection_failure_log_filter", "media_write_failure_log_filter", "notification_channels", "sql_export_job_name"] :
      length([
        for seg in split("variable \"", file("${path.module}/variables.tf")) : seg
        if startswith(seg, "${name}\"")
      ]) == 1
      &&
      alltrue([
        for seg in split("variable \"", file("${path.module}/variables.tf")) :
        !can(regex("\\n\\s*default\\s*=", seg))
        if startswith(seg, "${name}\"")
      ])
    ])
    error_message = "db_connection_failure_log_filter, media_write_failure_log_filter, notification_channels and sql_export_job_name must each be declared once with no default"
  }
}

run "creates_no_notification_channel_and_no_iam" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"google_monitoring_notification_channel\"", file("${path.module}/${f}")))
    ])
    error_message = "the module must not declare a google_monitoring_notification_channel (channels are made by hand, #24)"
  }

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"[a-z0-9_]*_iam_[a-z0-9_]*\"", file("${path.module}/${f}")))
    ])
    error_message = "the module must not declare any *_iam_* resource"
  }
}

# Amendment AC: no email-shaped string anywhere in modules/monitoring/** (tests included). .terraform/
# (provider binaries after init) is skipped; everything else in the module directory is text.
run "no_email_address_anywhere_in_the_module" {
  command = plan

  assert {
    condition = length([
      for f in fileset(path.module, "**") : f
      if !startswith(f, ".terraform/") && can(regex("[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}", file("${path.module}/${f}")))
    ]) == 0
    error_message = "an email-shaped string appears under modules/monitoring/: no address may be committed to this public repo (#24)"
  }
}

run "outputs" {
  command = apply

  assert {
    condition     = output.log_metric_names.db_connection_failures == "ecofolk-db-connection-failures" && output.log_metric_names.media_write_failures == "ecofolk-media-write-failures" && output.log_metric_names.sql_export_successes == "ecofolk-sql-export-successes"
    error_message = "log_metric_names must name both log-based metrics"
  }

  assert {
    condition     = output.alert_policy_names.api_5xx_rate == google_monitoring_alert_policy.api_5xx_rate.name && output.alert_policy_names.sql_export_stale == google_monitoring_alert_policy.sql_export_stale.name
    error_message = "alert_policy_names must carry the policies' resource names"
  }
}

run "rejects_no_channels" {
  command = plan

  variables {
    notification_channels = []
  }

  expect_failures = [var.notification_channels]
}

run "rejects_a_channel_that_is_not_a_resource_name" {
  command = plan

  variables {
    notification_channels = ["1234567890"]
  }

  expect_failures = [var.notification_channels]
}

run "rejects_an_empty_db_filter" {
  command = plan

  variables {
    db_connection_failure_log_filter = "  "
  }

  expect_failures = [var.db_connection_failure_log_filter]
}

run "rejects_an_empty_media_filter" {
  command = plan

  variables {
    media_write_failure_log_filter = ""
  }

  expect_failures = [var.media_write_failure_log_filter]
}

run "rejects_a_bad_service_name" {
  command = plan

  variables {
    api_service_name = "EcoFolk_API"
  }

  expect_failures = [var.api_service_name]
}

# Issue #13: env. dev keeps the log-based metric names; qa would get -qa; alert policies and uptime checks carry the env user label.

run "env_dev_keeps_its_names_and_labels" {
  command = plan

  assert {
    condition     = google_logging_metric.db_connection_failures.name == "ecofolk-db-connection-failures" && google_logging_metric.media_write_failures.name == "ecofolk-media-write-failures"
    error_message = "dev must keep both log-based metric names"
  }

  assert {
    condition     = alltrue([for p in [google_monitoring_alert_policy.api_5xx_rate, google_monitoring_alert_policy.db_connection_failures, google_monitoring_alert_policy.media_write_failures, google_monitoring_alert_policy.sql_export_stale] : p.user_labels.env == "dev"])
    error_message = "every alert policy (including sql_export_stale) must carry env = dev"
  }

  assert {
    condition     = google_monitoring_uptime_check_config.api_health.user_labels.env == "dev" && google_monitoring_uptime_check_config.web_root.user_labels.env == "dev"
    error_message = "both uptime checks must carry env = dev"
  }

  assert {
    condition = output.resource_names == [
      "google_logging_metric/ecofolk-db-connection-failures",
      "google_logging_metric/ecofolk-media-write-failures",
      "google_logging_metric/ecofolk-sql-export-successes",
    ]
    error_message = "resource_names must be every name the module sets (#13), got ${jsonencode(output.resource_names)}"
  }
}

run "env_qa_suffixes_names_and_labels" {
  command = plan

  variables {
    env = "qa"
  }

  assert {
    condition     = google_logging_metric.db_connection_failures.name == "ecofolk-db-connection-failures-qa" && google_logging_metric.media_write_failures.name == "ecofolk-media-write-failures-qa"
    error_message = "qa must suffix both log-based metric names with -qa"
  }

  assert {
    condition = (
      google_logging_metric.sql_export_successes.name == "ecofolk-sql-export-successes-qa" &&
      strcontains(google_monitoring_alert_policy.sql_export_stale.conditions[0].condition_absent[0].filter, "logging.googleapis.com/user/ecofolk-sql-export-successes-qa\"")
    )
    error_message = "qa must suffix the export metric with -qa and the stale-export alert must watch it"
  }

  assert {
    condition     = strcontains(google_monitoring_alert_policy.db_connection_failures.conditions[0].condition_threshold[0].filter, "logging.googleapis.com/user/ecofolk-db-connection-failures-qa\"")
    error_message = "the DB alert must watch the env's own metric"
  }

  assert {
    condition     = alltrue([for p in [google_monitoring_alert_policy.api_5xx_rate, google_monitoring_alert_policy.db_connection_failures, google_monitoring_alert_policy.media_write_failures, google_monitoring_alert_policy.sql_export_stale] : p.user_labels.env == "qa"])
    error_message = "every alert policy (including sql_export_stale) must carry env = qa"
  }

  assert {
    condition = output.resource_names == [
      "google_logging_metric/ecofolk-db-connection-failures-qa",
      "google_logging_metric/ecofolk-media-write-failures-qa",
      "google_logging_metric/ecofolk-sql-export-successes-qa",
    ]
    error_message = "resource_names must be every name the module sets (#13), got ${jsonencode(output.resource_names)}"
  }
}

run "env_refuses_staging" {
  command = plan

  variables {
    env = "staging"
  }

  expect_failures = [var.env]
}

# Issue #109 (Architect ruling on #111): the stale-export alert. The metric counts successful attempts of
# the nightly export's Cloud Scheduler job, from its execution log; the policy pages when it goes absent.
run "sql_export_metric_counts_successful_runs_of_the_export_job" {
  command = plan

  assert {
    condition = (
      google_logging_metric.sql_export_successes.project == "ecofolk-dev" &&
      google_logging_metric.sql_export_successes.metric_descriptor[0].metric_kind == "DELTA" &&
      google_logging_metric.sql_export_successes.metric_descriptor[0].value_type == "INT64"
    )
    error_message = "the export metric must be a DELTA/INT64 counter on var.project_id"
  }
}

# KNOWN-WRONG (structure, not presence): a failed attempt also writes an AttemptFinished entry. The filter
# must be exactly the AND of these clauses. A substring check passes a filter with "OR <anything>" appended,
# and because OR binds tighter than AND that turns the last clause into "(x OR <anything>)", so a failed
# run counts as a success and the alert stays quiet through a run of failures. Splitting on " AND " must
# give exactly this set, and no clause may carry an OR, a NOT or a parenthesis.
run "sql_export_metric_filter_is_exactly_the_and_of_its_clauses" {
  command = plan

  assert {
    condition = (
      length(split(" AND ", google_logging_metric.sql_export_successes.filter)) == 5 &&
      toset(split(" AND ", google_logging_metric.sql_export_successes.filter)) == toset([
        "resource.type=\"cloud_scheduler_job\"",
        "resource.labels.job_id=\"ecofolk-pg-nightly-export\"",
        "jsonPayload.\"@type\"=\"type.googleapis.com/google.cloud.scheduler.logging.AttemptFinished\"",
        "httpRequest.status>=200",
        "httpRequest.status<300",
      ])
    )
    error_message = "the export metric's filter must be exactly the AND of: the cloud_scheduler_job resource, this job's id, AttemptFinished, and httpRequest.status in [200, 300); got: ${google_logging_metric.sql_export_successes.filter}"
  }

  assert {
    condition     = !can(regex("(?i)(\\bOR\\b|\\bNOT\\b|[()]|(^|\\s)-)", google_logging_metric.sql_export_successes.filter))
    error_message = "the export metric's filter must have no OR, NOT, negation or grouping: any of them can re-admit a failed attempt"
  }
}

# The job id comes from the variable (modules/cloudsql's output in the roots), not a literal.
run "sql_export_follows_the_job_and_instance_variables" {
  command = plan

  variables {
    sql_export_job_name = "ecofolk-pg-canary-nightly-export"
    sql_instance_name   = "ecofolk-pg-canary"
  }

  assert {
    condition = (
      contains(split(" AND ", google_logging_metric.sql_export_successes.filter), "resource.labels.job_id=\"ecofolk-pg-canary-nightly-export\"") &&
      !strcontains(google_logging_metric.sql_export_successes.filter, "job_id=\"ecofolk-pg-nightly-export\"")
    )
    error_message = "the export metric must be scoped to var.sql_export_job_name only"
  }

  assert {
    condition = (
      strcontains(google_monitoring_alert_policy.sql_export_stale.documentation[0].content, "`ecofolk-pg-canary-nightly-export`") &&
      strcontains(google_monitoring_alert_policy.sql_export_stale.documentation[0].content, "`ecofolk-pg-canary`")
    )
    error_message = "the stale-export documentation must name the job and instance from the variables"
  }
}

# The roots pass modules/cloudsql's output, never a string literal (Architect ruling on #111).
run "roots_pass_the_job_id_from_modules_cloudsql" {
  command = plan

  assert {
    condition = alltrue([
      for env in ["dev", "prod"] :
      can(regex("\\n\\s*sql_export_job_name\\s*=\\s*module\\.cloudsql\\.export_job_name\\s*\\n", file("${path.module}/../../environments/${env}/main.tf")))
    ])
    error_message = "environments/dev and environments/prod must pass sql_export_job_name = module.cloudsql.export_job_name"
  }
}

# The DATA_READ audit-log metric is gone, not kept alongside: Data Access logs are off by default, so it
# would read as configured and never get a point (ef-qa's HOLD, Architect ruling on #111).
run "no_cloud_sql_audit_log_metric" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("cloudaudit\\.googleapis\\.com|cloudsql\\.instances\\.export|protoPayload", file("${path.module}/${f}")))
    ])
    error_message = "modules/monitoring must not match Cloud SQL's audit log (Data Access, off by default): the export alert watches the scheduler's execution log"
  }
}

run "sql_export_policy_is_absent_on_exactly_that_metric" {
  command = plan

  assert {
    condition = (
      length(google_monitoring_alert_policy.sql_export_stale.conditions) == 1 &&
      length(google_monitoring_alert_policy.sql_export_stale.conditions[0].condition_absent) == 1 &&
      length(google_monitoring_alert_policy.sql_export_stale.conditions[0].condition_threshold) == 0
    )
    error_message = "the stale-export policy must have exactly one condition, a condition_absent"
  }

  assert {
    condition = (
      google_monitoring_alert_policy.sql_export_stale.conditions[0].condition_absent[0].filter ==
      "metric.type=\"logging.googleapis.com/user/ecofolk-sql-export-successes\" AND resource.type=\"cloud_scheduler_job\""
    )
    error_message = "the stale-export policy's absence condition must watch exactly the ecofolk-sql-export-successes metric on cloud_scheduler_job"
  }

  # The API caps duration + alignment at 25 h; over 24 h so a daily gap is covered (#109, ruling on #111).
  assert {
    condition = (
      google_monitoring_alert_policy.sql_export_stale.conditions[0].condition_absent[0].duration == "68400s" &&
      google_monitoring_alert_policy.sql_export_stale.conditions[0].condition_absent[0].aggregations[0].alignment_period == "21600s"
    )
    error_message = "the stale-export alert must be 68400s (19 h) + 21600s (6 h) = 25 h"
  }

  assert {
    condition = (
      google_monitoring_alert_policy.sql_export_stale.project == "ecofolk-dev" &&
      google_monitoring_alert_policy.sql_export_stale.notification_channels == var.notification_channels
    )
    error_message = "the stale-export policy must be on var.project_id and notify exactly var.notification_channels"
  }

  assert {
    condition = alltrue([
      for s in ["What broke", "First thing to check", "`ecofolk-pg-nightly-export`", "Operations", "ecofolk-dev-sql-exports", "runbook.md#3-restore-from-the-nightly-export"] :
      strcontains(google_monitoring_alert_policy.sql_export_stale.documentation[0].content, s)
    ])
    error_message = "the stale-export documentation must say what broke, point at the scheduler job, Cloud SQL Operations and the bucket, and link runbook §3"
  }

  # What a success proves and what it doesn't (Architect ruling on #111).
  assert {
    condition = alltrue([
      for s in ["the Cloud SQL Admin API accepted the export request", "does **not** prove the export then completed", "§3.2 step 1", "gcloud sql operations list", "operationType=EXPORT"] :
      strcontains(google_monitoring_alert_policy.sql_export_stale.documentation[0].content, s)
    ])
    error_message = "the stale-export documentation must say a success proves the job fired and the Admin API accepted the request, that it does not prove the export completed, and point at runbook §3.2 step 1's operations list"
  }
}

run "rejects_a_job_name_that_is_a_resource_path" {
  command = plan

  variables {
    sql_export_job_name = "projects/ecofolk-dev/locations/northamerica-northeast1/jobs/ecofolk-pg-nightly-export"
  }

  expect_failures = [var.sql_export_job_name]
}

# The horizon rule, driven through the policy's real precondition. The first run is the old 23.5 h + 6 h
# (29.5 h), which the Monitoring API rejected; the second is 17 h + 6 h (23 h), which would page every
# morning before the next daily run. Both must fail; the 25 h and 24.5 h (fallback) cases must pass.
run "sql_export_horizon_over_25h_is_rejected" {
  command = plan
  variables {
    sql_export_absence_duration_seconds = 84600
    sql_export_alignment_period_seconds = 21600
  }
  expect_failures = [google_monitoring_alert_policy.sql_export_stale]
}

run "sql_export_horizon_of_24h_or_less_is_rejected" {
  command = plan
  variables {
    sql_export_absence_duration_seconds = 61200
    sql_export_alignment_period_seconds = 21600
  }
  expect_failures = [google_monitoring_alert_policy.sql_export_stale]
}

# Just over the cap: pins the upper bound at exactly 90000s (25 h).
run "sql_export_horizon_just_over_25h_is_rejected" {
  command = plan
  variables {
    sql_export_absence_duration_seconds = 68401
    sql_export_alignment_period_seconds = 21600
  }
  expect_failures = [google_monitoring_alert_policy.sql_export_stale]
}

run "sql_export_horizon_of_exactly_24h_is_rejected" {
  command = plan
  variables {
    sql_export_absence_duration_seconds = 64800
    sql_export_alignment_period_seconds = 21600
  }
  expect_failures = [google_monitoring_alert_policy.sql_export_stale]
}

run "sql_export_horizon_of_25h_passes" {
  command = plan
  assert {
    condition = (
      var.sql_export_absence_duration_seconds + var.sql_export_alignment_period_seconds > 86400 &&
      var.sql_export_absence_duration_seconds + var.sql_export_alignment_period_seconds <= 90000
    )
    error_message = "the default horizon must be over 24 h and at most 25 h"
  }
}

run "sql_export_fallback_horizon_of_24_5h_passes" {
  command = plan
  variables {
    sql_export_absence_duration_seconds = 66600
    sql_export_alignment_period_seconds = 21600
  }
  assert {
    condition     = google_monitoring_alert_policy.sql_export_stale.conditions[0].condition_absent[0].duration == "66600s"
    error_message = "the fallback duration must flow through to the policy"
  }
}

# The horizon variables exist so the tests can drive known-wrongs; no root may set them, or the policy's
# 24 h < horizon <= 25 h defaults could be overridden without a test noticing.
run "roots_do_not_set_the_horizon_test_variables" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset("${path.module}/../../environments", "*/*.tf") :
      !can(regex("sql_export_(absence_duration|alignment_period)_seconds", file("${path.module}/../../environments/${f}")))
    ])
    error_message = "no environments/* root may set sql_export_absence_duration_seconds or sql_export_alignment_period_seconds"
  }
}
