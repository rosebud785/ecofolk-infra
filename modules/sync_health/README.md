# modules/sync_health (ecofolk-infra#156, ecofolk#1349)

One Cloud Scheduler job, `sync-health`, that POSTs `{api_url}/internal/sync-health` at `0 6 * * *`
America/Chicago (06:00 CT daily): after the overnight syncs, outside #14's 22:15–04:45 CT dev Cloud SQL
stop (`docs/alerting-policy.md`). The app's job checks each watched source against its cadence and logs a
`sync_health_failed {job, reason}` warn line per problem; the alert on it is in `modules/monitoring`.

| input | default | dev (`environments/dev`) |
| --- | --- | --- |
| `api_url` | none | `module.cloudrun_api.uri` |
| `invoker_sa_email` | none | the existing sweep invoker, `sweep-invoker@<project>.iam.gserviceaccount.com` |

- **The schedule is fixed, not an input.** Changing it means changing `main.tf` and the test together.
- **Same credential as `modules/sync_usgs_water`.** An `oidc_token` for `invoker_sa_email`, audience = the
  endpoint URL; no static secret, no header. No IAM here.

## LOCAL FOLLOW-UP (app side)

Confirm `/internal/sync-health` accepts the sweep invoker's email and this audience. If it doesn't, the fix
is in the app; no IAM is added here.

## Read-back

```bash
gcloud scheduler jobs describe sync-health --project=<project> \
  --location=northamerica-northeast1 \
  --format="value(name,schedule,timeZone,state,httpTarget.httpMethod,httpTarget.uri,httpTarget.oidcToken.serviceAccountEmail,httpTarget.oidcToken.audience)"
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
| [google_cloud_scheduler_job.sync](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_scheduler_job) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| api_url | Base URL of the API (https://<host>, no path, no trailing slash); pass module.cloudrun_api.uri. | `string` | n/a | yes |
| env | Environment: dev, qa or prod. Sets the `env` label; qa (a namespace inside ecofolk-dev, #13) also suffixes each resource name with -qa. | `string` | n/a | yes |
| invoker_sa_email | Email of the existing sweep invoker service account (<id>@<project>.iam.gserviceaccount.com). | `string` | n/a | yes |
| project_id | GCP project id that owns the Scheduler job. | `string` | n/a | yes |
| region | Cloud Scheduler region. Must always be northamerica-northeast1 (Montréal), ef#391. | `string` | `"northamerica-northeast1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| audience | The OIDC audience the job's ID token carries (the endpoint URL); the API must expect exactly this. |
| job_name | Name of the sync-usgs-water Cloud Scheduler job. |
| resource_names | Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test). |
| scheduler_jobs | This module's Cloud Scheduler jobs (name, schedule, time_zone), for environments/dev's stop-window test (#99). |
| uri | The URL the job POSTs to; equals audience (#114's test asserts it). |
<!-- END_TF_DOCS -->
