# Issue #13 AC: with mock providers (no credentials, no GCP), (1) no resource name collides between the dev
# and qa compositions, which share ecofolk-dev, and (2) the qa root never declares a
# google_sql_database_instance, itself or through a module.
#
# The names come from each root's resource_names output, which concatenates every module's resource_names
# (a test can read module outputs, not resources inside modules). composition_is_covered fails if a module
# call in either root is left out of that output, so a new module can't skip the check.
#
# Not run by CI: the tf-test job only tests modules/* (same as environments/dev's #99 test). Run it locally:
#   terraform -chdir=environments/qa init -backend=false && terraform -chdir=environments/qa test
mock_provider "google" {}
mock_provider "google-beta" {}

# The data sources' ids must look real: modules/cloudrun_api validates the relative resource names (#45).
# (.tftest.hcl files are outside scripts/check-region-pin.sh's *.tf/*.tfvars scan.)
override_data {
  target = data.google_compute_network.dev
  values = {
    id = "projects/ecofolk-dev/global/networks/ecofolk"
  }
}

override_data {
  target = data.google_compute_subnetwork.dev
  values = {
    id = "projects/ecofolk-dev/regions/northamerica-northeast1/subnetworks/ecofolk-northamerica-northeast1"
  }
}

variables {
  project_id = "ecofolk-dev"
}

# Dev's composition, planned from this directory. Its own test (environments/dev/tests) uses the same inputs.
run "dev_plan" {
  command = plan

  module {
    source = "../dev"
  }

  variables {
    alert_notification_channels      = ["projects/ecofolk-dev/notificationChannels/1234567890"]
    db_connection_failure_log_filter = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.db_connect_failed\""
    media_write_failure_log_filter   = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.media_write_failed\""
  }

  # dev's main.tf imports the Firebase project; a mock provider can't import, so the resource is overridden.
  override_resource {
    target = module.web_hosting.google_firebase_project.this
  }

  assert {
    condition     = length(output.resource_names) > 0 && length(distinct(output.resource_names)) == length(output.resource_names)
    error_message = "dev's resource_names must be non-empty and have no duplicates: ${jsonencode(output.resource_names)}"
  }
}

run "qa_plan" {
  command = plan

  assert {
    condition = tolist(output.resource_names) == tolist([
      "google_sql_database/ecofolk_qa",
      "google_cloud_run_v2_service/ecofolk-api-qa",
    ])
    error_message = "qa must create exactly its own database and Cloud Run service, got ${jsonencode(output.resource_names)}"
  }

  assert {
    condition     = length(setintersection(toset(run.dev_plan.resource_names), toset(output.resource_names))) == 0
    error_message = "dev and qa resource names collide: ${jsonencode(setintersection(toset(run.dev_plan.resource_names), toset(output.resource_names)))}"
  }

  assert {
    condition     = output.database_name == "ecofolk_qa" && output.db_user_name == "ecofolk_qa_app"
    error_message = "qa must have its own database (ecofolk_qa) and DB user name (ecofolk_qa_app)"
  }

  assert {
    condition     = output.media_bucket == "ecofolk-dev-media" && output.media_prefix == "qa/"
    error_message = "qa must use the prefix qa/ in dev's media bucket ecofolk-dev-media"
  }

  assert {
    condition     = module.cloudrun_api.name == "ecofolk-api-qa"
    error_message = "qa's Cloud Run service must be ecofolk-api-qa"
  }
}

run "composition_is_covered" {
  command = plan

  module {
    source = "./tests/composition"
  }

  variables {
    qa_main_tf  = file("main.tf")
    qa_root_tf  = [for f in sort(fileset(".", "*.tf")) : file(f)]
    dev_main_tf = file("../dev/main.tf")
    module_sources = {
      for d in distinct([for f in fileset("../../modules", "*/*.tf") : dirname(f)]) :
      d => join("\n", [for f in sort(fileset("../../modules/${d}", "*.tf")) : file("../../modules/${d}/${f}")])
    }
  }

  # Keeps the call regex from passing by matching nothing.
  assert {
    condition     = output.qa_calls == tolist(["cloudrun_api", "sql_database"]) && length(output.dev_calls) == 13
    error_message = "expected qa to call cloudrun_api and sql_database and dev to make 13 module calls, found qa ${jsonencode(output.qa_calls)}, dev ${jsonencode(output.dev_calls)}"
  }

  assert {
    condition     = !output.qa_root_declares_instance && length(output.qa_modules_with_instance) == 0 && length(output.qa_unknown_sources) == 0
    error_message = "the qa root must never declare a google_sql_database_instance (#13): root ${output.qa_root_declares_instance}, modules ${jsonencode(output.qa_modules_with_instance)}, unread ${jsonencode(output.qa_unknown_sources)}"
  }

  assert {
    condition     = length(output.qa_uncovered) == 0 && length(output.dev_uncovered) == 0
    error_message = "module calls missing from resource_names: qa ${jsonencode(output.qa_uncovered)}, dev ${jsonencode(output.dev_uncovered)} (#13)"
  }
}

# The checks themselves, on known-wrongs.
run "known_wrong_cloudsql_call_in_qa_is_red" {
  command = plan

  module {
    source = "./tests/composition"
  }

  variables {
    qa_main_tf     = "module \"cloudsql\" {\n  source = \"../../modules/cloudsql\"\n}\n"
    qa_root_tf     = []
    dev_main_tf    = ""
    module_sources = { cloudsql = file("../../modules/cloudsql/main.tf") }
  }

  assert {
    condition     = output.qa_modules_with_instance == tolist(["cloudsql"]) && output.qa_uncovered == tolist(["cloudsql"])
    error_message = "a qa call to modules/cloudsql must be flagged as declaring an instance, and as missing from resource_names"
  }
}

run "known_wrong_instance_in_qa_root_is_red" {
  command = plan

  module {
    source = "./tests/composition"
  }

  variables {
    qa_main_tf     = ""
    qa_root_tf     = ["resource \"google_sql_database_instance\" \"x\" {}\n"]
    dev_main_tf    = ""
    module_sources = {}
  }

  assert {
    condition     = output.qa_root_declares_instance
    error_message = "a google_sql_database_instance in the qa root must be flagged"
  }
}

# Without the -qa suffix (env = "dev"), the Cloud Run service would collide with dev's: the check catches it.
run "known_wrong_unsuffixed_service_collides" {
  command = plan

  module {
    source = "../../modules/cloudrun_api"
  }

  variables {
    env             = "dev"
    service_account = format("%s@%s.iam.gserviceaccount.com", "ecofolk-api", "ecofolk-dev")
    network         = "projects/ecofolk-dev/global/networks/ecofolk"
    subnetwork      = "projects/ecofolk-dev/regions/northamerica-northeast1/subnetworks/ecofolk-northamerica-northeast1"
  }

  assert {
    condition     = length(setintersection(toset(run.dev_plan.resource_names), toset(output.resource_names))) == 1
    error_message = "an env = dev Cloud Run service in the same project must collide with dev's ecofolk-api"
  }
}
