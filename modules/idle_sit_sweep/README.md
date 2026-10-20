# modules/idle_sit_sweep (ecofolk-infra#17, cloud part of ecofolk#460)

One Cloud Scheduler job, `idle-sit-sweep`, that POSTs `{api_url}/internal/sweep-idle-sits` so the API
closes idle sits. Terraform half only; the endpoint's token check is ecofolk#1092.

| input | default | dev (`environments/dev`) |
| --- | --- | --- |
| `sweep_schedule` (America/Chicago) | `0 */2 * * *` (every 2 hours, under the 3h threshold) | `0 5-21/2 * * *` |
| `api_url` | none | `module.cloudrun_api.uri` |
| `invoker_sa_email` | none | `sweep-invoker@<project>.iam.gserviceaccount.com` |

- **Dev skips the night.** #14 stops dev Cloud SQL from 22:15 to 04:45 CT, so an overnight sweep would
  fail to reach the database and page through #24's alert. Dev's sweeps run 05:00 to 21:00, every
  2 hours. A sit left idle overnight still closes correctly at the first morning sweep: ecofolk#460 sets
  `ended_at` to the last activity, not to the sweep's run time.

## The credential: a Google-signed ID token, no secret

The job carries an `oidc_token` block: on every run, Cloud Scheduler mints a Google-signed OIDC ID token
for `invoker_sa_email` and sends it as `Authorization: Bearer <ID token>`. The token's audience is the
endpoint URL itself, `{api_url}/internal/sweep-idle-sits`. The API (ecofolk#1092) verifies the token
and accepts it only if the audience equals that URL, `email` equals its configured invoker SA, and
`email_verified` is true.

Why this, and not a static bearer value set on the job:

- **Nothing secret exists.** A static header is a literal stored in the job. Even with Terraform told
  to ignore it, every refresh reads the job back and writes the value into state. An ID token is
  minted per call, expires within the hour, and is never stored in the job or in state.
- **Terraform owns the whole job.** No header is set here or out of band, and there is no
  `ignore_changes`. There's nothing to rotate and no manual step after apply.
- **This is not invoker IAM.** The API service is public (it serves the web client); the token is
  how the API tells the scheduler apart from anyone else, by verifying it, not a Cloud Run invoker
  check.

`tests/idle_sit_sweep.tftest.hcl` asserts the `oidc_token` is there with the audience equal to the
endpoint URL, that Terraform sets no header, that this README is the only scanned file that names the
header, and that the old static credential's name appears in no scanned file.

## LOCAL FOLLOW-UP (ecofolk#460 / L1(a))

IAM is never written in this public repo:

1. Create service account `sweep-invoker` in the project, with **no roles**.
2. Confirm the identity that applies this job (tf-apply) can `actAs` `sweep-invoker`
   (`iam.serviceAccounts.actAs`, e.g. `roles/iam.serviceAccountUser` on that SA only). Without it,
   creating a job with an `oidc_token` for that SA fails.
3. Add the ef#395 inventory line.

## Read-back

```bash
gcloud scheduler jobs describe idle-sit-sweep --project=ecofolk-dev \
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
| [google_cloud_scheduler_job.sweep](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_scheduler_job) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| api_url | Base URL of the API (https://<host>, no path, no trailing slash); pass module.cloudrun_api.uri. | `string` | n/a | yes |
| env | Environment: dev, qa or prod. Sets the `env` label; qa (a namespace inside ecofolk-dev, #13) also suffixes each resource name with -qa. | `string` | n/a | yes |
| invoker_sa_email | Email of the sweep invoker service account (<id>@<project>.iam.gserviceaccount.com). | `string` | n/a | yes |
| project_id | GCP project id that owns the Scheduler job. | `string` | n/a | yes |
| region | Cloud Scheduler region. Must always be northamerica-northeast1 (Montréal), ef#391. | `string` | `"northamerica-northeast1"` | no |
| sweep_schedule | Cron schedule (5 fields, America/Chicago) for the idle-sit sweep. WARNING: the default 0 */2 * * * runs inside dev's 22:15–04:45 CT Cloud SQL stop (#14), so environments/dev must override it with a schedule that stays out of that window (#99). | `string` | `"0 */2 * * *"` | no |

## Outputs

| Name | Description |
|------|-------------|
| audience | The OIDC audience the job's ID token carries (the endpoint URL); the API must expect exactly this. |
| job_name | Name of the idle-sit sweep Cloud Scheduler job. |
| resource_names | Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test). |
| scheduler_jobs | This module's Cloud Scheduler jobs (name, schedule, time_zone), for environments/dev's stop-window test (#99). |
<!-- END_TF_DOCS -->
