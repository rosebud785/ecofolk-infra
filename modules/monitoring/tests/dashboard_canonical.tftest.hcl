# Issue #130: the dev dashboard showed an in-place update on every apply. GCP rewrites the stored
# dashboard_json (Deployer, #119 c6296932854): it adds "targetAxis": "Y1" to each data set and drops
# xPos/yPos keys whose value is 0, so a file without that shape never matches what the API reads back.
# dashboards/ecofolk.json is written in that canonical shape instead (no ignore_changes: that would hide
# real dashboard changes too). With a mock provider, assert the rendered dashboard is canonical, that the
# same predicates refuse the known-wrong fixtures, and that the content is otherwise what it was before
# #130 (tests/fixtures/ecofolk_before_130.json: same tiles, queries and thresholds).
mock_provider "google" {}

variables {
  project_id                       = "ecofolk-dev"
  notification_channels            = ["projects/ecofolk-dev/notificationChannels/1234567890"]
  db_connection_failure_log_filter = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.db_connect_failed\""
  media_write_failure_log_filter   = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.media_write_failed\""
  api_host                         = "api.example.test"
  web_host                         = "web.example.test"
  sql_export_job_name              = "ecofolk-pg-nightly-export"
  env                              = "dev"
}

run "rendered_dashboard_is_in_the_api_canonical_shape" {
  command = apply

  assert {
    condition = alltrue(flatten([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles : [
        for ds in t.widget.xyChart.dataSets : try(ds.targetAxis, null) == "Y1"
      ]
    ]))
    error_message = "every data set must carry \"targetAxis\": \"Y1\": the API adds it, so a data set without it diffs on every plan (#130)"
  }

  assert {
    condition = alltrue([
      for t in jsondecode(google_monitoring_dashboard.ecofolk.dashboard_json).mosaicLayout.tiles :
      try(t.xPos, null) != 0 && try(t.yPos, null) != 0
    ])
    error_message = "no tile may carry an xPos or yPos of 0: the API drops them, so they diff on every plan (#130)"
  }
}

# Known-wrongs: the same predicates, run over a data set without targetAxis and a tile with xPos 0, must
# refuse them. Without these, a predicate that matched everything would pass the real dashboard too.
run "known_wrong_dataset_without_target_axis_is_refused" {
  command = plan

  assert {
    condition = var.project_id == "ecofolk-dev" && !alltrue([
      for ds in jsondecode(file("${path.module}/tests/fixtures/dataset_without_target_axis.json")).widget.xyChart.dataSets :
      try(ds.targetAxis, null) == "Y1"
    ])
    error_message = "the targetAxis check must refuse tests/fixtures/dataset_without_target_axis.json"
  }

  # The fixture is otherwise canonical, so only the targetAxis check catches it.
  assert {
    condition = var.project_id == "ecofolk-dev" && alltrue([
      for t in [jsondecode(file("${path.module}/tests/fixtures/dataset_without_target_axis.json"))] :
      try(t.xPos, null) != 0 && try(t.yPos, null) != 0
    ])
    error_message = "dataset_without_target_axis.json must fail only the targetAxis check"
  }
}

run "known_wrong_tile_with_xpos_0_is_refused" {
  command = plan

  assert {
    condition = var.project_id == "ecofolk-dev" && !alltrue([
      for t in [jsondecode(file("${path.module}/tests/fixtures/tile_with_xpos_0.json"))] :
      try(t.xPos, null) != 0 && try(t.yPos, null) != 0
    ])
    error_message = "the zero-position check must refuse tests/fixtures/tile_with_xpos_0.json"
  }

  # The fixture is otherwise canonical, so only the zero-position check catches it.
  assert {
    condition = var.project_id == "ecofolk-dev" && alltrue([
      for ds in jsondecode(file("${path.module}/tests/fixtures/tile_with_xpos_0.json")).widget.xyChart.dataSets :
      try(ds.targetAxis, null) == "Y1"
    ])
    error_message = "tile_with_xpos_0.json must fail only the zero-position check"
  }
}

# The pre-#130 dashboard is itself known-wrong on both counts: it is the file that diffed on every apply.
run "known_wrong_pre_130_dashboard_is_refused" {
  command = plan

  assert {
    condition = var.project_id == "ecofolk-dev" && !alltrue(flatten([
      for t in jsondecode(file("${path.module}/tests/fixtures/ecofolk_before_130.json")).mosaicLayout.tiles : [
        for ds in t.widget.xyChart.dataSets : try(ds.targetAxis, null) == "Y1"
      ]
    ]))
    error_message = "the targetAxis check must refuse the pre-#130 dashboard"
  }

  assert {
    condition = var.project_id == "ecofolk-dev" && !alltrue([
      for t in jsondecode(file("${path.module}/tests/fixtures/ecofolk_before_130.json")).mosaicLayout.tiles :
      try(t.xPos, null) != 0 && try(t.yPos, null) != 0
    ])
    error_message = "the zero-position check must refuse the pre-#130 dashboard"
  }
}

# Content unchanged: with each data set's targetAxis removed and a missing xPos/yPos read as 0 (what the
# API means by an absent one), dashboards/ecofolk.json must equal the pre-#130 file tile for tile, so the
# tiles, titles, sizes, queries and thresholds (#104's: label and value only, no color) are all as they were.
run "dashboard_content_is_otherwise_unchanged" {
  command = plan

  assert {
    condition = var.project_id == "ecofolk-dev" && [
      for t in jsondecode(file("${path.module}/dashboards/ecofolk.json")).mosaicLayout.tiles : jsonencode(merge(t, {
        xPos = try(t.xPos, 0)
        yPos = try(t.yPos, 0)
        widget = merge(t.widget, { xyChart = merge(t.widget.xyChart, {
          dataSets = [for ds in t.widget.xyChart.dataSets : { for k, v in ds : k => v if k != "targetAxis" }]
        }) })
      }))
      ] == [
      for t in jsondecode(file("${path.module}/tests/fixtures/ecofolk_before_130.json")).mosaicLayout.tiles : jsonencode(merge(t, {
        xPos = try(t.xPos, 0)
        yPos = try(t.yPos, 0)
        widget = merge(t.widget, { xyChart = merge(t.widget.xyChart, {
          dataSets = [for ds in t.widget.xyChart.dataSets : { for k, v in ds : k => v if k != "targetAxis" }]
        }) })
      }))
    ]
    error_message = "dashboards/ecofolk.json must differ from the pre-#130 file only by targetAxis and dropped zero positions"
  }

  assert {
    condition = var.project_id == "ecofolk-dev" && (
      jsondecode(file("${path.module}/dashboards/ecofolk.json")).displayName ==
      jsondecode(file("${path.module}/tests/fixtures/ecofolk_before_130.json")).displayName &&
      jsondecode(file("${path.module}/dashboards/ecofolk.json")).mosaicLayout.columns ==
      jsondecode(file("${path.module}/tests/fixtures/ecofolk_before_130.json")).mosaicLayout.columns
    )
    error_message = "the dashboard's displayName and column count must be unchanged"
  }
}
