output "alert_policy_names" {
  value = {
    api_5xx_rate           = google_monitoring_alert_policy.api_5xx_rate.name
    db_connection_failures = google_monitoring_alert_policy.db_connection_failures.name
    media_write_failures   = google_monitoring_alert_policy.media_write_failures.name
  }
  description = "Resource names of the three alert policies."
}

output "log_metric_names" {
  value = {
    db_connection_failures = google_logging_metric.db_connection_failures.name
    media_write_failures   = google_logging_metric.media_write_failures.name
  }
  description = "Names of the two log-based metrics (logging.googleapis.com/user/<name>)."
}

# Issue #5: for ef#406's alert policies to reference (metric.label.check_id in an uptime_check filter).
output "uptime_check_ids" {
  value = {
    api_health = google_monitoring_uptime_check_config.api_health.uptime_check_id
    web_root   = google_monitoring_uptime_check_config.web_root.uptime_check_id
  }
  description = "Uptime check IDs of the API /health and web root checks."
}

# Issue #6: the dashboard's resource id (projects/<number>/dashboards/<id>).
output "dashboard_id" {
  value       = google_monitoring_dashboard.ecofolk.id
  description = "Resource id of the EcoFolk dashboard."
}

# #13: every name this module gives a resource (alert policies, uptime checks and the dashboard get
# server-assigned ids, so only the log-based metrics are named here), as <type>/<name>, for environments/qa's test that no
# name collides between dev and qa.
output "resource_names" {
  value = [
    "google_logging_metric/${google_logging_metric.db_connection_failures.name}",
    "google_logging_metric/${google_logging_metric.media_write_failures.name}",
  ]
  description = "Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test)."
}
