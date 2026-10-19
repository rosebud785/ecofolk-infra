# modules/sync_usgs_water (ecofolk-infra#98, Architect's ruling on #97 / ef#894)

One Cloud Scheduler job, `sync-usgs-water`, that POSTs `{api_url}/internal/sync-usgs-water` at
`0 5,11,17 * * *` America/Chicago (05:00, 11:00, 17:00 CT), the cadence in the app's table (ecofolk
`routes/internal.ts`, ef PR #1105). Until this job exists, that cadence does nothing live.

| input | default | dev (`environments/dev`) |
| --- | --- | --- |
| `api_url` | none | `module.cloudrun_api.uri` |
| `invoker_sa_email` | none | the existing sweep invoker, `sweep-invoker@<project>.iam.gserviceaccount.com` |

- **The schedule is fixed, not an input.** It must match the app's table, and all three runs are
  outside #14's 22:15–04:45 CT dev Cloud SQL stop (`docs/alerting-policy.md`). Changing it means
  changing `main.tf` and the test together.
- **Same credential as `modules/idle_sit_sweep`.** The job carries an `oidc_token` for
  `invoker_sa_email`, audience = the endpoint URL; the API verifies it (ecofolk#1092). No static
  secret, no header, no `ignore_changes`. See that module's README for why.
- **No IAM.** The invoker is the existing sweep invoker SA, passed in. This module creates no service
  account, binding or `actAs` grant (Architect's cloud spec on #98).

`tests/sync_usgs_water.tftest.hcl` asserts the time zone is America/Chicago, that no run hour falls in
22–04 (read from the planned job, expanded by `modules/idle_sit_sweep/tests/cron_hours`), the path, the
OIDC audience and invoker, that no header or `oauth_token` is set, and every validation.

## LOCAL FOLLOW-UP (ecofolk#1092, app side)

The API's token check compares the token's `email` with its configured invoker SA. Confirm
`/internal/sync-usgs-water` accepts the sweep invoker's email and this audience. If it doesn't, the fix
is in the app; no IAM is added here.

## Read-back

```bash
gcloud scheduler jobs describe sync-usgs-water --project=<project> \
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
| invoker_sa_email | Email of the existing sweep invoker service account (<id>@<project>.iam.gserviceaccount.com). | `string` | n/a | yes |
| project_id | GCP project id that owns the Scheduler job. | `string` | n/a | yes |
| region | Cloud Scheduler region. Must always be northamerica-northeast1 (Montréal), ef#391. | `string` | `"northamerica-northeast1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| audience | The OIDC audience the job's ID token carries (the endpoint URL); the API must expect exactly this. |
| job_name | Name of the sync-usgs-water Cloud Scheduler job. |
| scheduler_jobs | This module's Cloud Scheduler jobs (name, schedule, time_zone), for environments/dev's stop-window test (#99). |
<!-- END_TF_DOCS -->
