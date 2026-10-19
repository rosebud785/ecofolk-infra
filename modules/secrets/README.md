# modules/secrets

Secret Manager secret containers (no versions), with one replica in Montréal (ecofolk-infra#32).

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
| [google_secret_manager_secret.secret](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| env | Environment name, set as each secret's `env` label. | `string` | n/a | yes |
| project_id | GCP project id that owns the secrets. No default: every caller states its own project. | `string` | n/a | yes |
| region | Location of each secret's single user-managed replica. Must always be northamerica-northeast1 (Montréal), ef#391. | `string` | `"northamerica-northeast1"` | no |
| secret_names | Secret Manager secret ids to create as empty containers. Each is also the env var name the API reads it as. | `list(string)` | ```[ "POSTGRES_PASSWORD", "POSTGRES_INGEST_PASSWORD", "SWEEP_TOKEN", "NOAA_CDO_TOKEN" ]``` | no |

## Outputs

| Name | Description |
|------|-------------|
| secret_ids | Map from secret name to its id (projects/<project>/secrets/<name>), for the Cloud Run secretKeyRef mapping (ecofolk-infra#66). |
<!-- END_TF_DOCS -->
