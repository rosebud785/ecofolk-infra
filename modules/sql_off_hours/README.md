# modules/sql_off_hours (ecofolk-infra#14, C14)

Dev only. Two Cloud Scheduler jobs stop the dev Cloud SQL instance out of ops hours and start it again.
Each job PATCHes `settings.activationPolicy` through the Cloud SQL Admin API:

| job | schedule (America/Chicago) | activationPolicy |
| --- | --- | --- |
| `<instance>-off-hours-stop` | `15 22 * * *` (22:15 CT) | `NEVER` |
| `<instance>-off-hours-start` | `45 4 * * *` (04:45 CT) | `ALWAYS` |

- **The start comes before #2's 05:00 CT maintenance window, 05:15 export and 05:30 backup.** Cloud SQL
  skips the automated backup of a stopped instance, and the Admin `export` call fails against one
  (Architect amendment on #14). The start time lives in one local in `main.tf`.
- **Stopping dev also stops the QA namespace (#13),** which shares the instance. That's intended.
- **Prod never gets these jobs.** `environments/prod` doesn't call this module, and `project_id`
  refuses a `*-prod` id.
- `enable_off_hours` (default `true`) set to `false` creates neither job.
- `modules/cloudsql` ignores `settings.activation_policy`, so an apply from `main` while dev is stopped
  leaves it stopped.

Both jobs run as `service_account_email`, the `ops-scheduler` account from #2.

**LOCAL FOLLOW-UP (L1(a), ef#885):** grant `ops-scheduler` `roles/cloudsql.editor` on `ecofolk-dev`
only. IAM is never written in this repo.

## Read-back

These print named fields only, never the whole job (its `httpTarget` carries the OAuth token config):

```bash
gcloud scheduler jobs describe ecofolk-pg-off-hours-stop --project=ecofolk-dev \
  --location=northamerica-northeast1 --format="value(name,schedule,timeZone,state,httpTarget.httpMethod)"
gcloud scheduler jobs describe ecofolk-pg-off-hours-start --project=ecofolk-dev \
  --location=northamerica-northeast1 --format="value(name,schedule,timeZone,state,httpTarget.httpMethod)"
gcloud sql instances describe ecofolk-pg --project=ecofolk-dev \
  --format="value(name,state,settings.activationPolicy)"
```

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
| [google_cloud_scheduler_job.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_scheduler_job) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| enable_off_hours | Create the 22:15 CT stop and 04:45 CT start jobs. False creates neither, so the instance runs around the clock. | `bool` | `true` | no |
| instance_name | Name of the Cloud SQL instance to stop and start; pass module.cloudsql.instance_name. | `string` | n/a | yes |
| project_id | GCP project id of the dev project that owns the instance. Must not be a *-prod project. | `string` | n/a | yes |
| region | Cloud Scheduler region. Must always be northamerica-northeast1 (Montréal), ef#391. | `string` | `"northamerica-northeast1"` | no |
| service_account_email | Email of the service account the stop and start jobs run as (ops-scheduler in the dev project). Created locally, never here. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| job_names | Names of the Cloud Scheduler jobs, keyed stop and start. Empty when enable_off_hours is false. |
<!-- END_TF_DOCS -->
