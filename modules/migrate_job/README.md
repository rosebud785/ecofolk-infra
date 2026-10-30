# modules/migrate_job (ecofolk#1169, G1 part 1)

The schema migrator as a Cloud Run v2 **Job**, `ecofolk-migrate`: it runs the same image as the API, over
Direct VPC egress into the API's subnet, as its own keyless service account. That account is a Cloud SQL
**IAM database user** (`modules/cloudsql`, `migrate_service_account_email`), so the job holds no password
and maps no secret. The deploy script (ecofolk#408) updates the job's image to the pushed digest and
executes it with `--wait` before `gcloud run deploy`; the module ignores later image changes.

No IAM here (CONTRIBUTING: the boundary). The bindings, the service account and the in-database grants are
the LOCAL FOLLOW-UP list at the top of `main.tf`; the schema-owner decision is item 5 there: the migrator
owns the schema and may `CREATE EXTENSION postgis, vector`, the API's runtime DB user gets DML only.

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
| [google_cloud_run_v2_job.migrate](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_job) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| args | Container args: the migrate CLI. Terraform owns them; the deploy script updates the image only. | `list(string)` | ```[ "/app/packages/db/dist/cli/migrate.js" ]``` | no |
| command | Container entrypoint. Terraform owns it; the deploy script updates the image only. | `list(string)` | ```[ "node" ]``` | no |
| env | Environment: dev, qa or prod. Sets the `env` label; qa (a namespace inside ecofolk-dev, #13) also suffixes the job name with -qa. | `string` | n/a | yes |
| env_vars | Plain environment variables for the container (DB host, name, IAM user). NON-SECRET values only: this lands in state and in the public repo. | `map(string)` | `{}` | no |
| image | Container image for the first execution. Defaults to Google's public placeholder; the deploy script owns the image. | `string` | `"us-docker.pkg.dev/cloudrun/container/hello"` | no |
| name | Cloud Run job name (lowercase letters, digits and hyphens). A qa job gets -qa appended (#13). | `string` | `"ecofolk-migrate"` | no |
| network | VPC for Direct VPC egress, as its relative resource name (.id), not self-link; pass module.network.network_id. | `string` | n/a | yes |
| project_id | GCP project id that owns the job. No default: every caller states its own project. | `string` | n/a | yes |
| region | Cloud Run region. Must always be northamerica-northeast1 (Montréal), ef#391; pass module.project.region. | `string` | `"northamerica-northeast1"` | no |
| secret_env | Env var name -> Secret Manager secret, mapped by secret_key_ref at version latest. Only POSTGRES_INGEST_PASSWORD is accepted (the value the migrator sets on the ingest role, not a login). References only, never values. | `map(string)` | `{}` | no |
| service_account | Email of the keyless migrate service account the job runs as. Created locally, never here. | `string` | n/a | yes |
| subnetwork | Subnet for Direct VPC egress, as its relative resource name (.id), not self-link; pass module.network.subnet_id. | `string` | n/a | yes |
| timeout_seconds | Task timeout in seconds. A migration that runs longer fails the execution, and the deploy is refused. | `number` | `600` | no |

## Outputs

| Name | Description |
|------|-------------|
| env_vars | The plain environment variables set on the container (non-secret), for environments' tests. |
| name | Cloud Run job name, for the deploy script's `gcloud run jobs update/execute` (ecofolk#1169). |
| resource_names | Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test). |
| secret_env | Env var name -> Secret Manager secret reference set on the container (references only), for environments' tests. |
<!-- END_TF_DOCS -->
