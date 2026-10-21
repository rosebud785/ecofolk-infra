# modules/monitoring

Alerts on the API 5xx rate, DB connections and media write failures, with channels by ID only (ecofolk-infra#24), and on no successful nightly Cloud SQL export (ecofolk-infra#109); HTTPS uptime checks on the API `/health` and the web root (ecofolk-infra#5); one dashboard, its JSON in `dashboards/ecofolk.json` (ecofolk-infra#6).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| google | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| google | ~> 5.0 |

## Resources

| Name | Type |
|------|------|
| [google_logging_metric.db_connection_failures](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_logging_metric.media_write_failures](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_logging_metric.sql_export_successes](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_metric) | resource |
| [google_monitoring_alert_policy.api_5xx_rate](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.db_connection_failures](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.media_write_failures](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_alert_policy.sql_export_stale](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy) | resource |
| [google_monitoring_dashboard.ecofolk](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_dashboard) | resource |
| [google_monitoring_uptime_check_config.api_health](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_uptime_check_config) | resource |
| [google_monitoring_uptime_check_config.web_root](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_uptime_check_config) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| api_host | Hostname of the EcoFolk API (e.g. its Cloud Run run.app host), probed at https://<api_host>/health. | `string` | n/a | yes |
| api_service_name | Name of the API's Cloud Run service, for the 5xx policy's filter. | `string` | `"ecofolk-api"` | no |
| db_connection_failure_log_filter | Cloud Logging filter matching one log entry per failed database connection attempt by the API. Supplied by L-ALERT. | `string` | n/a | yes |
| db_max_connections | The Cloud SQL tier's max_connections, drawn as the connections tile's threshold. 25 = db-f1-micro. | `number` | `25` | no |
| media_write_failure_log_filter | Cloud Logging filter matching one log entry per failed media upload/write by the API. Supplied by L-ALERT. | `string` | n/a | yes |
| notification_channels | Notification channel resource names (projects/<project>/notificationChannels/<n>) every policy notifies. IDs only: never an address. | `list(string)` | n/a | yes |
| project_id | GCP project id the alert policies and log-based metrics live in. No default: every caller states its own project. | `string` | n/a | yes |
| sql_export_absence_duration_seconds | Absence duration of the stale-export alert, in seconds (19 h). With the alignment period the horizon must be over 24 h and at most 25 h. | `number` | `68400` | no |
| sql_export_alignment_period_seconds | Alignment period of the stale-export alert, in seconds (6 h). With the absence duration the horizon must be over 24 h and at most 25 h. | `number` | `21600` | no |
| sql_export_job_name | Id of the nightly export's Cloud Scheduler job, for the stale-export alert (pass module.cloudsql.export_job_name). | `string` | n/a | yes |
| sql_instance_name | Name of the Cloud SQL instance the dashboard's database tiles watch and the stale-export alert names (modules/cloudsql's instance_name). | `string` | `"ecofolk-pg"` | no |
| web_host | Hostname of the EcoFolk web build (modules/web_hosting: <project>-web.web.app), probed at https://<web_host>/. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| alert_policy_names | Resource names of the four alert policies. |
| dashboard_id | Resource id of the EcoFolk dashboard. |
| log_metric_names | Names of the three log-based metrics (logging.googleapis.com/user/<name>). sql_export_successes counts successful runs of the nightly export job (#109). |
| uptime_check_ids | Uptime check IDs of the API /health and web root checks. |
<!-- END_TF_DOCS -->
