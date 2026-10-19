# modules/cloudsql

Cloud SQL Postgres 16: private IP only, backups on, the IAM auth flag set (ecofolk-infra#18).

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
| [google_cloud_scheduler_job.sql_export](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_scheduler_job) | resource |
| [google_sql_database.ecofolk](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database) | resource |
| [google_sql_database_instance.postgres](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database_instance) | resource |
| [google_storage_bucket.sql_exports](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| deletion_protection | Sets both Terraform's deletion_protection and the instance's settings.deletion_protection_enabled. | `bool` | `true` | no |
| export_service_account_email | Email of the service account the nightly export job runs as (the ops-scheduler account in the dev project). Created locally, never here. | `string` | n/a | yes |
| instance_name | Cloud SQL instance name (lowercase letters, digits and hyphens). | `string` | `"ecofolk-pg"` | no |
| private_network | Self-link of the VPC the instance takes its private IP in; pass module.network.network_self_link. | `string` | n/a | yes |
| project_id | GCP project id that owns the instance. No default: every caller states its own project. | `string` | n/a | yes |
| region | Cloud SQL region. Must always be northamerica-northeast1 (Montréal), ef#391. | `string` | `"northamerica-northeast1"` | no |
| tier | Machine tier. Must be on the policy allowlist (policy/data.json); callers pass a literal or omit it. | `string` | `"db-f1-micro"` | no |

## Outputs

| Name | Description |
|------|-------------|
| connection_name | Instance connection name (<project>:<region>:<instance>), for the Cloud SQL connector. |
| database_name | Name of the application database. |
| export_bucket_name | Bucket the nightly export lands in (<project_id>-sql-exports). |
| export_job_name | Name of the Cloud Scheduler job that runs the nightly export. |
| instance_name | The instance's name, for modules/sql_off_hours' stop and start jobs (#14). |
| instance_service_account_email | The instance's own service account. The export writes as it, so LOCAL FOLLOW-UP L1(a) grants it write on the export bucket. |
| private_ip_address | The instance's private IP inside the PSA range. There is no public IP. |
| scheduler_jobs | This module's Cloud Scheduler jobs (name, schedule, time_zone), for environments/dev's stop-window test (#99). |
<!-- END_TF_DOCS -->
