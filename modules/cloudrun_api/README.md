# modules/cloudrun_api

The API on Cloud Run v2: scale-to-zero, Direct VPC egress (ecofolk-infra#19).

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
| [google_cloud_run_v2_service.api](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| env | Environment: dev, qa or prod. Sets the `env` label; qa (a namespace inside ecofolk-dev, #13) also suffixes each resource name with -qa. | `string` | n/a | yes |
| env_vars | Plain environment variables for the container. NON-SECRET values only: this lands in state and in the public repo. | `map(string)` | `{}` | no |
| image | Container image for the first revision. Defaults to Google's public placeholder; later deploys own the image. | `string` | `"us-docker.pkg.dev/cloudrun/container/hello"` | no |
| max_instance_count | Upper bound on instances. At most 3 (C7); callers pass a literal or omit it. | `number` | `3` | no |
| name | Cloud Run service name (lowercase letters, digits and hyphens). A qa service gets -qa appended (#13). | `string` | `"ecofolk-api"` | no |
| network | VPC for Direct VPC egress, as its relative resource name (.id), not self-link; pass module.network.network_id. | `string` | n/a | yes |
| project_id | GCP project id that owns the service. No default: every caller states its own project. | `string` | n/a | yes |
| region | Cloud Run region. Must always be northamerica-northeast1 (Montréal), ef#391; pass module.project.region. | `string` | `"northamerica-northeast1"` | no |
| secret_env | Env var name -> Secret Manager secret, mapped by secret_key_ref at version latest. References only, never values. | `map(string)` | `{}` | no |
| service_account | Email of the runtime service account the service runs as. Created locally (L-RUN), never here. | `string` | n/a | yes |
| subnetwork | Subnet for Direct VPC egress, as its relative resource name (.id), not self-link; pass module.network.subnet_id. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| env_vars | The plain environment variables set on the container (non-secret), for environments' tests (#114). |
| name | Cloud Run service name. |
| resource_names | Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test). |
| uri | The service's run.app URI. Not callable by the public until L-RUN adds the invoker binding. |
<!-- END_TF_DOCS -->
