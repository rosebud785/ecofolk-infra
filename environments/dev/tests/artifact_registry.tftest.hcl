# Issue #119: with mock providers (no credentials, no GCP), environments/dev instantiates
# modules/artifact_registry as repository "ecofolk", exposes its id as artifact_registry_repository_id, and
# the repository carries the module's two cleanup policies.
#
# A test can read a root's outputs, not resources inside its modules, and the module has no output for its
# cleanup policies. So the id is asserted on the composed dev plan, and the policies on the module itself,
# planned with the same arguments main.tf passes it (dev_call_args checks main.tf passes nothing else).
#
# Not run by CI until #107: the tf-test job only tests modules/*. Run it locally:
#   terraform -chdir=environments/dev init -backend=false && terraform -chdir=environments/dev test
mock_provider "google" {}
mock_provider "google-beta" {}

# main.tf imports the Firebase project; a mock provider can't import, so the resource is overridden.
override_resource {
  target = module.web_hosting.google_firebase_project.this
}

variables {
  project_id                       = "ecofolk-dev"
  alert_notification_channels      = ["projects/ecofolk-dev/notificationChannels/1234567890"]
  db_connection_failure_log_filter = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.db_connect_failed\""
  media_write_failure_log_filter   = "resource.type=\"cloud_run_revision\" AND jsonPayload.event=\"test.media_write_failed\""
}

run "dev_repository_id" {
  command = plan

  assert {
    condition     = output.artifact_registry_repository_id == "ecofolk"
    error_message = "environments/dev must create the Artifact Registry repository \"ecofolk\" and expose it as artifact_registry_repository_id, got ${jsonencode(output.artifact_registry_repository_id)}"
  }
}

# The module call passes only source, project_id, repository_id and depends_on: no region (the module's
# pinned default) and nothing else that could change what the policies run below see.
run "dev_call_args" {
  command = plan

  module {
    source = "./tests/module_call"
  }

  variables {
    main_tf = file("main.tf")
    name    = "artifact_registry"
  }

  assert {
    condition     = output.source == "../../modules/artifact_registry"
    error_message = "module \"artifact_registry\" must be called from ../../modules/artifact_registry, got ${jsonencode(output.source)}"
  }

  assert {
    condition     = output.arguments == tolist(["depends_on", "project_id", "repository_id", "source"])
    error_message = "module \"artifact_registry\" must pass only project_id, repository_id and depends_on (region from the module default), got ${jsonencode(output.arguments)}"
  }
}

run "dev_repository_cleanup_policies" {
  command = plan

  module {
    source = "../../modules/artifact_registry"
  }

  variables {
    project_id    = "ecofolk-dev"
    repository_id = "ecofolk"
  }

  assert {
    condition     = google_artifact_registry_repository.docker.location == "northamerica-northeast1"
    error_message = "the dev repository must be in northamerica-northeast1"
  }

  assert {
    condition     = google_artifact_registry_repository.docker.cleanup_policy_dry_run == false
    error_message = "the dev repository's cleanup policies must delete, not dry-run"
  }

  assert {
    condition     = length(google_artifact_registry_repository.docker.cleanup_policies) == 2
    error_message = "the dev repository must have exactly two cleanup policies"
  }

  assert {
    condition = length([
      for p in google_artifact_registry_repository.docker.cleanup_policies : p
      if p.id == "keep-10-most-recent" && p.action == "KEEP"
      && length(p.most_recent_versions) == 1
      && one(p.most_recent_versions).keep_count == 10
    ]) == 1
    error_message = "the dev repository must KEEP the 10 most recent versions"
  }

  assert {
    condition = length([
      for p in google_artifact_registry_repository.docker.cleanup_policies : p
      if p.id == "delete-untagged-older-than-7d" && p.action == "DELETE"
      && length(p.condition) == 1
      && one(p.condition).tag_state == "UNTAGGED"
      && one(p.condition).older_than == "604800s"
    ]) == 1
    error_message = "the dev repository must DELETE untagged images older than 604800s (7 days)"
  }
}
