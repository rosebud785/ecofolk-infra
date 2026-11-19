# modules/check_config_job (ecofolk-infra#169, ecofolk#1419)

The pre-deploy config check as a Cloud Run v2 **Job**, `ecofolk-check-config`: it runs the same image as the API with
`node dist/checkConfig.js` (`loadApiConfig`, then a `SELECT 1` as the runtime and the ingest database user), over
Direct VPC egress into the API's subnet. The deploy script (ecofolk `scripts/deploy/deploy-dev.sh`, step 3b)
updates the job's image to the pushed digest and executes it with `--wait` before the migrate job and
`gcloud run deploy`; a failing execution refuses the deploy. The module ignores later image changes.

**The job must match the service exactly, or the check proves nothing.** The caller passes the SAME `env_vars`,
`secret_env` and `service_account` it passes to `modules/cloudrun_api`, from one shared local
(`environments/dev/main.tf`), never a copy. `environments/dev/tests/check_config_job.tftest.hcl` fails if the job's
env keys, secret refs or service account diverge from the service's.

No IAM here (CONTRIBUTING: the boundary). The job runs as the API's runtime service account, so it needs nothing
the service lacks. The one new binding, a local follow-up, is listed at the top of `main.tf`: `roles/run.developer`
for the deploy identity on this job only.

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
| [google_cloud_run_v2_job.check_config](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_job) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| args | Container args: the check-config entry (ecofolk#1419), relative to the image's WORKDIR. Terraform owns them; the deploy script updates the image only. | `list(string)` | ```[ "dist/checkConfig.js" ]``` | no |
| command | Container entrypoint. Terraform owns it; the deploy script updates the image only. | `list(string)` | ```[ "node" ]``` | no |
| env | Environment: dev, qa or prod. Sets the `env` label; qa (a namespace inside ecofolk-dev, #13) also suffixes the job name with -qa. | `string` | n/a | yes |
| env_vars | Plain environment variables for the container: the same map the API service gets. NON-SECRET values only: this lands in state and in the public repo. | `map(string)` | `{}` | no |
| image | Container image for the first execution. Defaults to Google's public placeholder; the deploy script owns the image. | `string` | `"us-docker.pkg.dev/cloudrun/container/hello"` | no |
| name | Cloud Run job name (lowercase letters, digits and hyphens). A qa job gets -qa appended (#13). | `string` | `"ecofolk-check-config"` | no |
| network | VPC for Direct VPC egress, as its relative resource name (.id), not self-link; pass module.network.network_id. | `string` | n/a | yes |
| project_id | GCP project id that owns the job. No default: every caller states its own project. | `string` | n/a | yes |
| region | Cloud Run region. Must always be northamerica-northeast1 (Montréal), ef#391; pass module.project.region. | `string` | `"northamerica-northeast1"` | no |
| secret_env | Env var name -> Secret Manager secret, mapped by secret_key_ref at version latest: the same map the API service gets. References only, never values. | `map(string)` | `{}` | no |
| service_account | Email of the API's runtime service account: the job runs as the service does. Created locally, never here. | `string` | n/a | yes |
| subnetwork | Subnet for Direct VPC egress, as its relative resource name (.id), not self-link; pass module.network.subnet_id. | `string` | n/a | yes |
| timeout_seconds | Task timeout in seconds. The check connects twice and loads a config, so minutes is plenty; a longer run fails the execution and the deploy is refused. | `number` | `300` | no |

## Outputs

| Name | Description |
|------|-------------|
| env_vars | The plain environment variables set on the container (non-secret), for environments' tests. |
| name | Cloud Run job name, for the deploy script's `gcloud run jobs update/execute` (ecofolk#1419). |
| resource_names | Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test). |
| secret_env | Env var name -> Secret Manager secret reference set on the container (references only), for environments' tests. |
| service_account | The service account the job runs as, for environments' tests that it is the API's. |
<!-- END_TF_DOCS -->
