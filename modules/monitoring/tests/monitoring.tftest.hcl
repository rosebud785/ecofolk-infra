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
}

run "three_policies_exist_and_notify_the_channels" {
  command = plan

  assert {
    condition = alltrue([
      for p in [
        google_monitoring_alert_policy.api_5xx_rate,
        google_monitoring_alert_policy.db_connection_failures,
        google_monitoring_alert_policy.media_write_failures,
      ] : p.project == "ecofolk-dev" && p.notification_channels == var.notification_channels
    ])
    error_message = "all three alert policies must exist on var.project_id and notify exactly var.notification_channels"
  }

  assert {
    condition = alltrue([
      for p in [
        google_monitoring_alert_policy.api_5xx_rate,
        google_monitoring_alert_policy.db_connection_failures,
        google_monitoring_alert_policy.media_write_failures,
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
# fails the apply. A default isn't visible in a plan, so read variables.tf: each block (the text from
# `variable "<name>"` up to the next `variable "`) must exist and must have no `default =` line.
run "filter_and_channel_variables_have_no_default" {
  command = plan

  assert {
    condition = alltrue([
      for name in ["db_connection_failure_log_filter", "media_write_failure_log_filter", "notification_channels"] :
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
    error_message = "db_connection_failure_log_filter, media_write_failure_log_filter and notification_channels must each be declared once with no default"
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
    condition     = output.log_metric_names.db_connection_failures == "ecofolk-db-connection-failures" && output.log_metric_names.media_write_failures == "ecofolk-media-write-failures"
    error_message = "log_metric_names must name both log-based metrics"
  }

  assert {
    condition     = output.alert_policy_names.api_5xx_rate == google_monitoring_alert_policy.api_5xx_rate.name
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
    condition     = alltrue([for p in [google_monitoring_alert_policy.api_5xx_rate, google_monitoring_alert_policy.db_connection_failures, google_monitoring_alert_policy.media_write_failures] : p.user_labels.env == "dev"])
    error_message = "every alert policy must carry env = dev"
  }

  assert {
    condition     = google_monitoring_uptime_check_config.api_health.user_labels.env == "dev" && google_monitoring_uptime_check_config.web_root.user_labels.env == "dev"
    error_message = "both uptime checks must carry env = dev"
  }

  assert {
    condition = output.resource_names == [
      "google_logging_metric/ecofolk-db-connection-failures",
      "google_logging_metric/ecofolk-media-write-failures",
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
    condition     = strcontains(google_monitoring_alert_policy.db_connection_failures.conditions[0].condition_threshold[0].filter, "logging.googleapis.com/user/ecofolk-db-connection-failures-qa\"")
    error_message = "the DB alert must watch the env's own metric"
  }

  assert {
    condition     = alltrue([for p in [google_monitoring_alert_policy.api_5xx_rate, google_monitoring_alert_policy.db_connection_failures, google_monitoring_alert_policy.media_write_failures] : p.user_labels.env == "qa"])
    error_message = "every alert policy must carry env = qa"
  }

  assert {
    condition = output.resource_names == [
      "google_logging_metric/ecofolk-db-connection-failures-qa",
      "google_logging_metric/ecofolk-media-write-failures-qa",
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
