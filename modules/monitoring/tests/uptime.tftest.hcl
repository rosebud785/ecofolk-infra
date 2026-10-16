# Issue #5 AC: with a mock provider (no credentials, no GCP), assert the two uptime checks are HTTPS on a
# 5-minute period from 3 checker regions, probe /health on the API host and / on the web host, take
# their hosts from the variables, and that the check IDs are outputs. Each host validation refuses a
# bad value. No alert policy or notification channel on the checks (ef#406 routes them).
mock_provider "google" {}

variables {
  project_id                       = "ecofolk-dev"
  notification_channels            = ["projects/ecofolk-dev/notificationChannels/1234567890"]
  db_connection_failure_log_filter = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.db_connect_failed\""
  media_write_failure_log_filter   = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.media_write_failed\""
  api_host                         = "api.example.test"
  web_host                         = "web.example.test"
}

run "both_checks_are_https_every_5_minutes_from_3_regions" {
  command = plan

  assert {
    condition = alltrue([
      for c in [
        google_monitoring_uptime_check_config.api_health,
        google_monitoring_uptime_check_config.web_root,
      ] : c.project == "ecofolk-dev" && c.period == "300s" && length(c.selected_regions) == 3
    ])
    error_message = "both uptime checks must be on var.project_id with period 300s and exactly 3 checker regions"
  }

  assert {
    condition = alltrue([
      for c in [
        google_monitoring_uptime_check_config.api_health,
        google_monitoring_uptime_check_config.web_root,
      ] : c.http_check[0].use_ssl == true && c.http_check[0].validate_ssl == true && c.http_check[0].port == 443
    ])
    error_message = "both uptime checks must be HTTPS (use_ssl, validate_ssl, port 443)"
  }
}

run "paths_are_health_and_root" {
  command = plan

  assert {
    condition     = google_monitoring_uptime_check_config.api_health.http_check[0].path == "/health"
    error_message = "the API check must probe /health"
  }

  assert {
    condition     = google_monitoring_uptime_check_config.web_root.http_check[0].path == "/"
    error_message = "the web check must probe the root, /"
  }
}

run "hosts_follow_the_variables" {
  command = plan

  variables {
    api_host = "api-canary.example.test"
    web_host = "web-canary.example.test"
  }

  assert {
    condition = (
      google_monitoring_uptime_check_config.api_health.monitored_resource[0].type == "uptime_url" &&
      google_monitoring_uptime_check_config.api_health.monitored_resource[0].labels.host == "api-canary.example.test" &&
      google_monitoring_uptime_check_config.api_health.monitored_resource[0].labels.project_id == "ecofolk-dev"
    )
    error_message = "the API check must be an uptime_url on var.api_host in var.project_id"
  }

  assert {
    condition = (
      google_monitoring_uptime_check_config.web_root.monitored_resource[0].type == "uptime_url" &&
      google_monitoring_uptime_check_config.web_root.monitored_resource[0].labels.host == "web-canary.example.test" &&
      google_monitoring_uptime_check_config.web_root.monitored_resource[0].labels.project_id == "ecofolk-dev"
    )
    error_message = "the web check must be an uptime_url on var.web_host in var.project_id"
  }
}

run "outputs_the_check_ids" {
  command = apply

  assert {
    condition = (
      output.uptime_check_ids.api_health == google_monitoring_uptime_check_config.api_health.uptime_check_id &&
      output.uptime_check_ids.web_root == google_monitoring_uptime_check_config.web_root.uptime_check_id
    )
    error_message = "uptime_check_ids must carry both checks' uptime_check_id"
  }
}

run "no_policy_or_channel_on_the_checks" {
  command = plan

  assert {
    condition     = !can(regex("google_monitoring_(alert_policy|notification_channel)", file("${path.module}/uptime.tf")))
    error_message = "uptime.tf must not declare an alert policy or notification channel: routing is ef#406's (#5)"
  }
}

run "rejects_an_api_host_with_a_scheme" {
  command = plan

  variables {
    api_host = "https://api.example.test"
  }

  expect_failures = [var.api_host]
}

run "rejects_a_web_host_with_a_path" {
  command = plan

  variables {
    web_host = "web.example.test/"
  }

  expect_failures = [var.web_host]
}
