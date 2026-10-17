# dashboard.tf — one Cloud Monitoring dashboard, "EcoFolk" (ecofolk-infra#6, row C6): the one place to look.
#
# The dashboard's JSON is checked in as dashboards/ecofolk.json (CI's `dashboard-json` job runs jq over
# it) and rendered here with templatefile(). Tiles:
#   - API on Cloud Run: request count, p50/p95 latency, 5xx count, instance count;
#   - Cloud SQL: CPU, connections against the tier maximum (var.db_max_connections), disk;
#   - pass rate of #5's two uptime checks (uptime.tf), by their check IDs.
# tests/dashboard.tftest.hcl asserts every tile's metric type is on an allowlist, because a typo in a
# metric type is otherwise only caught at apply.
#
# Every placeholder sits inside a JSON string, so the checked-in file stays valid JSON. The one number,
# the connections threshold, is the string "__DB_MAX_CONNECTIONS__" in the file and is swapped for the
# bare number after rendering.
#
# What is deliberately NOT here: no alert policy (alerts.tf owns those), no IAM of any kind.
# Dashboards are project-level, not regional: nothing here takes a region.
#
# LOCAL FOLLOW-UP (ecofolk): this module is not yet wired into environments/dev (see alerts.tf). When it
# is, pass sql_instance_name (module.cloudsql's instance) if it isn't the default, and db_max_connections
# if the tier isn't db-f1-micro.

locals {
  dashboard_json = replace(
    templatefile("${path.module}/dashboards/ecofolk.json", {
      api_service_name    = var.api_service_name
      sql_database_id     = "${var.project_id}:${var.sql_instance_name}"
      api_health_check_id = google_monitoring_uptime_check_config.api_health.uptime_check_id
      web_root_check_id   = google_monitoring_uptime_check_config.web_root.uptime_check_id
    }),
    "\"__DB_MAX_CONNECTIONS__\"",
    tostring(var.db_max_connections),
  )
}

resource "google_monitoring_dashboard" "ecofolk" {
  project        = var.project_id
  dashboard_json = local.dashboard_json
}
