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
