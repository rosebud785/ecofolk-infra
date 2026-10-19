# modules/artifact_registry

Region-pinned Docker repository in Artifact Registry, with cleanup policies (ecofolk-infra#4).

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
| [google_artifact_registry_repository.docker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| description | Human-readable description shown on the repository. | `string` | `"EcoFolk container images"` | no |
| project_id | GCP project id that owns the repository. No default: every caller states its own project. | `string` | n/a | yes |
| region | Artifact Registry location. Must always be northamerica-northeast1 (Montréal), ef#391. | `string` | `"northamerica-northeast1"` | no |
| repository_id | Artifact Registry repository id (lowercase letters, digits and hyphens). | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| docker_host | Docker registry host for this repository (<location>-docker.pkg.dev). |
| location | The repository's location. Always northamerica-northeast1 — see variables.tf. |
| repository_id | The Artifact Registry repository id. |
<!-- END_TF_DOCS -->
