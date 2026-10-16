# main.tf — dev billing kill-switch (ecofolk-infra#15): a Pub/Sub topic for the dedicated dev budget's
# notifications, feeding a Cloud Functions (2nd gen) Python function that unlinks billing from the project
# once the budget's actual cost reaches budgetAmount x var.unlink_threshold. A budget only alerts; this
# is Google's standard pattern for an actual cap.
#
# DEV ONLY. NEVER PROD: unlinking prod's billing takes the beta down. The function unlinks only a project
# on var.project_allowlist (default ["ecofolk-dev"]), and only on messages from the budget named
# var.budget_display_name (default ecofolk-dev-killswitch); every other budget, ecofolk-all included, is
# ignored. C7 (policy/billing_killswitch.rego) refuses any allowlist holding a *-prod id.
#
# Not here (ecofolk#885, L1(b), local): creating the budget (gross cost, --credit-types-treatment=
# exclude-all-credits), pointing it at this topic, and every IAM grant. See README.md.
#
# Region: every regional piece (topic storage, function, trigger, source bucket) is var.region, validated
# to northamerica-northeast1 (ef#391).
#
# The runtime service account is NOT created here. It is created locally under var.service_account_id
# (Architect, #15: ecofolk-killswitch), and tf-apply is granted actAs on it there.
#
# LOCAL FOLLOW-UP (ecofolk#885, L1(b)): roles/billing.projectManager for the runtime SA on ecofolk-dev only,
# so it can call cloudbilling.projects.updateBillingInfo.
# LOCAL FOLLOW-UP (ecofolk#885): roles/iam.serviceAccountUser for tf-apply on the runtime SA only (actAs),
# which the Architect says the paste already grants.
# LOCAL FOLLOW-UP (ecofolk#885): roles/eventarc.eventReceiver for the trigger SA (the same runtime SA) on
# ecofolk-dev, and roles/run.invoker for it on this function's underlying Cloud Run service only; without
# them the Eventarc trigger can't deliver the Pub/Sub message to the function.
# IAM is never written in this repo by a cloud session.
locals {
  service_account_email = "${var.service_account_id}@${var.project_id}.iam.gserviceaccount.com"

  # APIs this module needs beyond modules/project's list (run, cloudbuild, artifactregistry and storage
  # are already enabled there). Enabled here, not in modules/project, so prod's API list doesn't grow.
  apis = [
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbilling.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.apis)

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

# The budget (created locally) publishes its notifications here. Messages are stored in Montréal only.
resource "google_pubsub_topic" "budget" {
  project = var.project_id
  name    = var.topic_name

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }

  labels = {
    env       = "dev"
    component = "billing-killswitch"
  }

  depends_on = [google_project_service.apis]
}

# The function's source, zipped from function/ at plan time. Written under the root's .terraform/
# (git-ignored); the object name carries the zip's hash, so a code change redeploys the function.
data "archive_file" "source" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.root}/.terraform/tmp/billing-killswitch-source.zip"
  excludes    = ["__pycache__"]
}

# Holds only the build source zip. Private, uniform access (C7 storage rule), Montréal.
resource "google_storage_bucket" "source" {
  project  = var.project_id
  name     = "${var.project_id}-killswitch-src"
  location = upper(var.region)

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Only rebuildable source zips live here.
  force_destroy = true

  labels = {
    env       = "dev"
    component = "billing-killswitch"
  }
}

resource "google_storage_bucket_object" "source" {
  bucket = google_storage_bucket.source.name
  name   = "billing-killswitch-${data.archive_file.source.output_md5}.zip"
  source = data.archive_file.source.output_path
}

resource "google_cloudfunctions2_function" "killswitch" {
  project     = var.project_id
  name        = var.function_name
  location    = var.region
  description = "Unlinks billing from an allowlisted dev project when budget ${var.budget_display_name} reaches ${var.unlink_threshold} x its amount (ecofolk-infra#15)."

  build_config {
    runtime     = "python312"
    entry_point = "on_budget_message"

    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.source.name
      }
    }
  }

  service_config {
    # One message at a time is plenty; scale to zero between budget notifications.
    min_instance_count             = 0
    max_instance_count             = 1
    available_memory               = "256M"
    timeout_seconds                = 60
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = local.service_account_email

    environment_variables = {
      TARGET_PROJECT_ID   = var.project_id
      UNLINK_ALLOWLIST    = join(",", var.project_allowlist)
      BUDGET_DISPLAY_NAME = var.budget_display_name
      UNLINK_THRESHOLD    = tostring(var.unlink_threshold)
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.budget.id
    service_account_email = local.service_account_email
    # Budgets re-publish their status several times a day, so a missed message is retried by the next one.
    retry_policy = "RETRY_POLICY_DO_NOT_RETRY"
  }

  labels = {
    env       = "dev"
    component = "billing-killswitch"
  }

  depends_on = [google_project_service.apis]
}
