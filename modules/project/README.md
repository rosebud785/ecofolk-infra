# modules/project

Enables the BUILD_PLAN §11.1 APIs on one project.

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
| [google_project_service.apis](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| enabled_apis | GCP APIs to enable on the project (BUILD_PLAN.md §11.1, plus Artifact Registry for ecofolk-infra#4, Identity Toolkit for ecofolk-infra#20, Cloud Storage for ecofolk-infra#21, Firebase Hosting for ecofolk-infra#22 and Secret Manager for ecofolk-infra#32 and Cloud Scheduler for ecofolk-infra#2). | `list(string)` | ```[ "run.googleapis.com", "sqladmin.googleapis.com", "cloudbuild.googleapis.com", "aiplatform.googleapis.com", "firebase.googleapis.com", "compute.googleapis.com", "servicenetworking.googleapis.com", "artifactregistry.googleapis.com", "identitytoolkit.googleapis.com", "storage.googleapis.com", "firebasehosting.googleapis.com", "secretmanager.googleapis.com", "cloudscheduler.googleapis.com" ]``` | no |
| project_id | GCP project id — "ecofolk-dev" or "ecofolk-prod" (BUILD_PLAN.md §11.1). No default: every environment must state its own project explicitly. | `string` | n/a | yes |
| region | GCP region. Must always be northamerica-northeast1 (Montréal, hydro-powered) — Andy's hard constraint, ef#391. Do not override this per-environment. | `string` | `"northamerica-northeast1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| project_id | The GCP project id this module was instantiated for. |
| region | The (pinned) region this module was instantiated for. Always northamerica-northeast1 — see variables.tf. |
<!-- END_TF_DOCS -->
