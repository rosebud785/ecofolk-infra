# Issue #6 AC: with a mock provider (no credentials, no GCP), assert the one dashboard renders to valid
# JSON with every placeholder filled, that every tile's metric type is on the allowlist below (a typo in
# a metric type otherwise only fails at apply), that each spec tile is there, that the tiles follow the
# service, instance and uptime check IDs, and that each new variable's validation refuses a bad value.
# CI's `dashboard-json` job runs jq over the checked-in dashboards/ecofolk.json itself.
mock_provider "google" {}

variables {
  project_id                       = "ecofolk-dev"
  notification_channels            = ["projects/ecofolk-dev/notificationChannels/1234567890"]
  db_connection_failure_log_filter = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.db_connect_failed\""
  media_write_failure_log_filter   = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.media_write_failed\""
  api_host                         = "api.example.test"
  web_host                         = "web.example.test"
  sql_export_job_name              = "ecofolk-pg-nightly-export"
}

run "one_dashboard_in_the_project_with_valid_json" {
  command = apply

  assert {
    condition     = google_monitoring_dashboard.ecofolk.project == "ecofolk-dev"
    error_message = "the dashboard must be in var.project_id"
  }

  assert {
    condition     = can(jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json))
    error_message = "the rendered dashboard_json must be valid JSON"
  }

  # The Monitoring API's Threshold (#104), checked against the v1 discovery document (revision 20261011)
  # and google/monitoring/dashboard/v1/metrics.proto on 2026-10-20:
  #   https://cloud.google.com/monitoring/api/ref_v3/rest/v1/projects.dashboards#Threshold
  # Its fields are label, value, color, direction and targetAxis, but "Color is not allowed in a XyChart"
  # and "Direction is not allowed in a XyChart", so an xyChart threshold may carry only label, value and
  # targetAxis. A mock provider never sees the API's 400 (#94's first apply failed on tile 5's
  # "color": "RED", "direction": "ABOVE"), so the shape is guarded here as an allowlist.
  assert {
    condition = alltrue(flatten([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles : [
        for th in try(t.widget.xyChart.thresholds, []) : alltrue([
          for k in keys(th) : contains(["label", "value", "targetAxis"], k)
        ])
      ]
    ]))
    error_message = "an xyChart threshold may carry only label, value and targetAxis: the Monitoring API refuses color and direction"
  }

  # Each enum field a threshold carries must hold one of the API's values (same reference as above).
  assert {
    condition = alltrue(flatten([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles : [
        for th in try(t.widget.xyChart.thresholds, []) : (
          contains(["COLOR_UNSPECIFIED", "YELLOW", "RED"], try(th.color, "COLOR_UNSPECIFIED")) &&
          contains(["DIRECTION_UNSPECIFIED", "ABOVE", "BELOW"], try(th.direction, "DIRECTION_UNSPECIFIED")) &&
          contains(["TARGET_AXIS_UNSPECIFIED", "Y1", "Y2"], try(th.targetAxis, "TARGET_AXIS_UNSPECIFIED"))
        )
      ]
    ]))
    error_message = "a threshold's color, direction or targetAxis is not a Monitoring API enum value"
  }

  assert {
    condition     = jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).displayName == "EcoFolk"
    error_message = "the dashboard must be named EcoFolk"
  }

  assert {
    condition = (
      !strcontains(google_monitoring_dashboard.ecofolk.dashboard_json, "$${") &&
      !strcontains(google_monitoring_dashboard.ecofolk.dashboard_json, "__DB_MAX_CONNECTIONS__")
    )
    error_message = "every placeholder in dashboards/ecofolk.json must be filled"
  }

  assert {
    condition     = output.dashboard_id == google_monitoring_dashboard.ecofolk.id
    error_message = "dashboard_id must be the dashboard's id"
  }
}

# The allowlist. Every tile must be an xyChart whose every data set has a filter naming exactly one
# metric type, and that type must be on this list; and every type on the list must be used by some tile,
# so a dropped tile fails too.
run "every_tile_metric_type_is_on_the_allowlist" {
  command = apply

  assert {
    condition = alltrue([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles :
      can(t.widget.xyChart.dataSets) && length(t.widget.xyChart.dataSets) > 0
    ])
    error_message = "every tile must be an xyChart with at least one data set (so the allowlist check sees it)"
  }

  assert {
    condition = alltrue(flatten([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles : [
        for ds in t.widget.xyChart.dataSets :
        length(regexall("metric\\.type=\"[^\"]+\"", ds.timeSeriesQuery.timeSeriesFilter.filter)) == 1
      ]
    ]))
    error_message = "every data set's filter must name exactly one metric.type"
  }

  assert {
    condition = alltrue(flatten([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles : [
        for ds in t.widget.xyChart.dataSets : contains([
          "run.googleapis.com/request_count",
          "run.googleapis.com/request_latencies",
          "run.googleapis.com/container/instance_count",
          "cloudsql.googleapis.com/database/cpu/utilization",
          "cloudsql.googleapis.com/database/postgresql/num_backends",
          "cloudsql.googleapis.com/database/disk/utilization",
          "monitoring.googleapis.com/uptime_check/check_passed",
        ], regex("metric\\.type=\"([^\"]+)\"", ds.timeSeriesQuery.timeSeriesFilter.filter)[0])
      ]
    ]))
    error_message = "a tile uses a metric type that is not on the allowlist (typo?)"
  }

  assert {
    condition = length(setsubtract([
      "run.googleapis.com/request_count",
      "run.googleapis.com/request_latencies",
      "run.googleapis.com/container/instance_count",
      "cloudsql.googleapis.com/database/cpu/utilization",
      "cloudsql.googleapis.com/database/postgresql/num_backends",
      "cloudsql.googleapis.com/database/disk/utilization",
      "monitoring.googleapis.com/uptime_check/check_passed",
      ], flatten([
        for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles : [
          for ds in t.widget.xyChart.dataSets : regex("metric\\.type=\"([^\"]+)\"", ds.timeSeriesQuery.timeSeriesFilter.filter)[0]
        ]
    ]))) == 0
    error_message = "every allowlisted metric type must be charted by some tile"
  }
}

run "spec_tiles_are_all_there" {
  command = apply

  # 4 Cloud Run + 3 Cloud SQL + 1 uptime.
  assert {
    condition     = length(jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles) == 8
    error_message = "the dashboard must have exactly the 8 spec tiles"
  }

  # p50 and p95 latency.
  assert {
    condition = length(setsubtract(["REDUCE_PERCENTILE_50", "REDUCE_PERCENTILE_95"], flatten([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles : [
        for ds in t.widget.xyChart.dataSets : ds.timeSeriesQuery.timeSeriesFilter.aggregation.crossSeriesReducer
        if strcontains(ds.timeSeriesQuery.timeSeriesFilter.filter, "run.googleapis.com/request_latencies")
      ]
    ]))) == 0
    error_message = "the latency tile must chart both p50 and p95"
  }

  # 5xx count: a request_count series filtered to the 5xx class.
  assert {
    condition = anytrue(flatten([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles : [
        for ds in t.widget.xyChart.dataSets :
        strcontains(ds.timeSeriesQuery.timeSeriesFilter.filter, "run.googleapis.com/request_count") &&
        strcontains(ds.timeSeriesQuery.timeSeriesFilter.filter, "metric.label.response_code_class=\"5xx\"")
      ]
    ]))
    error_message = "there must be a 5xx count tile (request_count, response_code_class 5xx)"
  }

  # Connections against the tier maximum: a threshold line at var.db_max_connections, as a number.
  assert {
    condition = anytrue([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles :
      strcontains(t.widget.xyChart.dataSets[0].timeSeriesQuery.timeSeriesFilter.filter, "postgresql/num_backends") &&
      try(t.widget.xyChart.thresholds[0].value, null) == 25
    ])
    error_message = "the connections tile must draw the tier maximum (default 25) as a numeric threshold"
  }

  # Uptime pass rate: fraction of checks passed.
  assert {
    condition = alltrue(flatten([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles : [
        for ds in t.widget.xyChart.dataSets : ds.timeSeriesQuery.timeSeriesFilter.aggregation.perSeriesAligner == "ALIGN_FRACTION_TRUE"
        if strcontains(ds.timeSeriesQuery.timeSeriesFilter.filter, "uptime_check/check_passed")
      ]
    ]))
    error_message = "the uptime tile must chart the pass rate (ALIGN_FRACTION_TRUE)"
  }
}

run "tiles_follow_the_service_instance_and_check_ids" {
  command = apply

  variables {
    api_service_name   = "ecofolk-api-canary"
    sql_instance_name  = "ecofolk-pg-canary"
    db_max_connections = 100
  }

  # Every Cloud Run filter names the service; every Cloud SQL filter names <project>:<instance>.
  assert {
    condition = alltrue(flatten([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles : [
        for ds in t.widget.xyChart.dataSets :
        strcontains(ds.timeSeriesQuery.timeSeriesFilter.filter, "resource.label.service_name=\"ecofolk-api-canary\"")
        if strcontains(ds.timeSeriesQuery.timeSeriesFilter.filter, "run.googleapis.com/")
      ]
    ]))
    error_message = "every Cloud Run tile must filter on var.api_service_name"
  }

  assert {
    condition = alltrue(flatten([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles : [
        for ds in t.widget.xyChart.dataSets :
        strcontains(ds.timeSeriesQuery.timeSeriesFilter.filter, "resource.label.database_id=\"ecofolk-dev:ecofolk-pg-canary\"")
        if strcontains(ds.timeSeriesQuery.timeSeriesFilter.filter, "cloudsql.googleapis.com/")
      ]
    ]))
    error_message = "every Cloud SQL tile must filter on database_id <project_id>:<sql_instance_name>"
  }

  # The uptime tile charts exactly #5's two checks, by ID.
  assert {
    condition = toset(flatten([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles : [
        for ds in t.widget.xyChart.dataSets : regex("metric\\.label\\.check_id=\"([^\"]+)\"", ds.timeSeriesQuery.timeSeriesFilter.filter)[0]
        if strcontains(ds.timeSeriesQuery.timeSeriesFilter.filter, "uptime_check/check_passed")
      ]
    ])) == toset([output.uptime_check_ids.api_health, output.uptime_check_ids.web_root])
    error_message = "the uptime tile must chart exactly the two #5 checks, by uptime_check_id"
  }

  assert {
    condition = anytrue([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles :
      try(t.widget.xyChart.thresholds[0].value, null) == 100
    ])
    error_message = "the connections threshold must follow var.db_max_connections"
  }
}

run "no_policy_channel_or_iam_in_dashboard_tf" {
  command = plan

  assert {
    condition     = !can(regex("google_monitoring_(alert_policy|notification_channel)|_iam_", file("${path.module}/dashboard.tf")))
    error_message = "dashboard.tf must not declare an alert policy, notification channel or IAM (#6)"
  }
}

run "rejects_a_bad_sql_instance_name" {
  command = plan

  variables {
    sql_instance_name = "Ecofolk_PG"
  }

  expect_failures = [var.sql_instance_name]
}

run "rejects_zero_max_connections" {
  command = plan

  variables {
    db_max_connections = 0
  }

  expect_failures = [var.db_max_connections]
}

run "rejects_fractional_max_connections" {
  command = plan

  variables {
    db_max_connections = 2.5
  }

  expect_failures = [var.db_max_connections]
}

# Known-wrongs for the allowlist above: the same predicate, run over thresholds GCP refuses, must say "not
# allowed". Without these, an allowlist that matched everything would pass the real dashboard too.
run "xychart_threshold_allowlist_refuses_color_and_direction" {
  command = plan

  assert {
    condition     = var.project_id == "ecofolk-dev" && !alltrue([for k in keys(jsondecode("{\"label\":\"x\",\"value\":1,\"color\":\"RED\"}")) : contains(["label", "value", "targetAxis"], k)])
    error_message = "the allowlist must refuse a threshold with color"
  }

  assert {
    condition     = var.project_id == "ecofolk-dev" && !alltrue([for k in keys(jsondecode("{\"label\":\"x\",\"value\":1,\"direction\":\"ABOVE\"}")) : contains(["label", "value", "targetAxis"], k)])
    error_message = "the allowlist must refuse a threshold with direction"
  }

  assert {
    condition     = var.project_id == "ecofolk-dev" && alltrue([for k in keys(jsondecode("{\"label\":\"x\",\"value\":1,\"targetAxis\":\"Y1\"}")) : contains(["label", "value", "targetAxis"], k)])
    error_message = "the allowlist must accept label, value and targetAxis"
  }
}

# #104 known-wrong: tests/fixtures/tile5_rejected_2026-10-19.json is tile 5 (the connections tile, 0-based
# index 5) exactly as #94 applied it on 2026-10-19, when the Monitoring API answered 400. The field
# allowlist above, run over it, must refuse it. Its color and direction (RED, ABOVE) are valid enum values,
# so only the allowlist catches it: the enum check below must still accept it.
run "known_wrong_tile5_threshold_of_2026_10_19_is_refused" {
  command = plan

  assert {
    condition = var.project_id == "ecofolk-dev" && !alltrue([
      for th in jsondecode(file("${path.module}/tests/fixtures/tile5_rejected_2026-10-19.json")).widget.xyChart.thresholds : alltrue([
        for k in keys(th) : contains(["label", "value", "targetAxis"], k)
      ])
    ])
    error_message = "the xyChart threshold allowlist must refuse tile 5's rejected 2026-10-19 threshold"
  }

  assert {
    condition = var.project_id == "ecofolk-dev" && alltrue([
      for th in jsondecode(file("${path.module}/tests/fixtures/tile5_rejected_2026-10-19.json")).widget.xyChart.thresholds : (
        contains(["COLOR_UNSPECIFIED", "YELLOW", "RED"], try(th.color, "COLOR_UNSPECIFIED")) &&
        contains(["DIRECTION_UNSPECIFIED", "ABOVE", "BELOW"], try(th.direction, "DIRECTION_UNSPECIFIED")) &&
        contains(["TARGET_AXIS_UNSPECIFIED", "Y1", "Y2"], try(th.targetAxis, "TARGET_AXIS_UNSPECIFIED"))
      )
    ])
    error_message = "RED and ABOVE are API enum values: the enum check must accept them (the allowlist is what refuses tile 5)"
  }
}

# Known-wrongs for the enum check: the same predicate must refuse a value that isn't in the API's enum.
run "threshold_enum_check_refuses_values_outside_the_api_enums" {
  command = plan

  assert {
    condition = var.project_id == "ecofolk-dev" && !alltrue([
      for th in [jsondecode("{\"label\":\"x\",\"value\":1,\"color\":\"GREEN\"}")] : (
        contains(["COLOR_UNSPECIFIED", "YELLOW", "RED"], try(th.color, "COLOR_UNSPECIFIED")) &&
        contains(["DIRECTION_UNSPECIFIED", "ABOVE", "BELOW"], try(th.direction, "DIRECTION_UNSPECIFIED")) &&
        contains(["TARGET_AXIS_UNSPECIFIED", "Y1", "Y2"], try(th.targetAxis, "TARGET_AXIS_UNSPECIFIED"))
      )
    ])
    error_message = "the enum check must refuse color GREEN (not in the API's Color enum)"
  }

  assert {
    condition = var.project_id == "ecofolk-dev" && !alltrue([
      for th in [jsondecode("{\"label\":\"x\",\"value\":1,\"direction\":\"UP\"}")] : (
        contains(["COLOR_UNSPECIFIED", "YELLOW", "RED"], try(th.color, "COLOR_UNSPECIFIED")) &&
        contains(["DIRECTION_UNSPECIFIED", "ABOVE", "BELOW"], try(th.direction, "DIRECTION_UNSPECIFIED")) &&
        contains(["TARGET_AXIS_UNSPECIFIED", "Y1", "Y2"], try(th.targetAxis, "TARGET_AXIS_UNSPECIFIED"))
      )
    ])
    error_message = "the enum check must refuse direction UP (not in the API's Direction enum)"
  }

  assert {
    condition = var.project_id == "ecofolk-dev" && !alltrue([
      for th in [jsondecode("{\"label\":\"x\",\"value\":1,\"targetAxis\":\"Y3\"}")] : (
        contains(["COLOR_UNSPECIFIED", "YELLOW", "RED"], try(th.color, "COLOR_UNSPECIFIED")) &&
        contains(["DIRECTION_UNSPECIFIED", "ABOVE", "BELOW"], try(th.direction, "DIRECTION_UNSPECIFIED")) &&
        contains(["TARGET_AXIS_UNSPECIFIED", "Y1", "Y2"], try(th.targetAxis, "TARGET_AXIS_UNSPECIFIED"))
      )
    ])
    error_message = "the enum check must refuse targetAxis Y3 (not in the API's TargetAxis enum)"
  }

  assert {
    condition = var.project_id == "ecofolk-dev" && alltrue([
      for th in [jsondecode("{\"label\":\"x\",\"value\":1,\"targetAxis\":\"Y2\"}")] : (
        contains(["COLOR_UNSPECIFIED", "YELLOW", "RED"], try(th.color, "COLOR_UNSPECIFIED")) &&
        contains(["DIRECTION_UNSPECIFIED", "ABOVE", "BELOW"], try(th.direction, "DIRECTION_UNSPECIFIED")) &&
        contains(["TARGET_AXIS_UNSPECIFIED", "Y1", "Y2"], try(th.targetAxis, "TARGET_AXIS_UNSPECIFIED"))
      )
    ])
    error_message = "the enum check must accept targetAxis Y2"
  }
}
