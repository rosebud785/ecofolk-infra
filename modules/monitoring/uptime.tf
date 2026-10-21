# uptime.tf — uptime checks for the API's /health and the web root (ecofolk-infra#5, row C5).
#
# Gap this closes: the alerts in alerts.tf (ef#406) fire on 5xx, DB and media write failures, and none
# of them fires when the service is simply unreachable. These two checks probe from outside over HTTPS.
#
# What is deliberately NOT here (spec on #5):
#   - no alert policy on the checks and no notification channel: routing is ef#406's decision, so the
#     check IDs are outputs (uptime_check_ids) for its policies to reference;
#   - no IAM of any kind.
#
# Uptime checks are project-level, not regional: nothing here takes a region. selected_regions are the
# places Google probes FROM, not where anything runs. Google has no Canadian checker location, so the
# three North American ones are used (3 is the API's minimum).
#
# LOCAL FOLLOW-UP (ecofolk): this module is not yet wired into environments/dev (see alerts.tf). When it
# is, pass api_host (the API's Cloud Run hostname, no scheme) and web_host (the web build's Hosting
# hostname, <project>-web.web.app per modules/web_hosting).

locals {
  # Spec: HTTPS, 5-minute period, 3 checker regions.
  uptime_period          = "300s"
  uptime_timeout         = "10s"
  uptime_checker_regions = ["USA_OREGON", "USA_IOWA", "USA_VIRGINIA"]
  uptime_api_health_path = "/health"
  uptime_web_root_path   = "/"
  uptime_https_port      = 443
}

resource "google_monitoring_uptime_check_config" "api_health" {
  project          = var.project_id
  display_name     = "EcoFolk API: /health"
  user_labels      = { env = var.env }
  period           = local.uptime_period
  timeout          = local.uptime_timeout
  selected_regions = local.uptime_checker_regions

  http_check {
    path           = local.uptime_api_health_path
    port           = local.uptime_https_port
    use_ssl        = true
    validate_ssl   = true
    request_method = "GET"
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.api_host
    }
  }
}

resource "google_monitoring_uptime_check_config" "web_root" {
  project          = var.project_id
  display_name     = "EcoFolk web: /"
  user_labels      = { env = var.env }
  period           = local.uptime_period
  timeout          = local.uptime_timeout
  selected_regions = local.uptime_checker_regions

  http_check {
    path           = local.uptime_web_root_path
    port           = local.uptime_https_port
    use_ssl        = true
    validate_ssl   = true
    request_method = "GET"
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.web_host
    }
  }
}
