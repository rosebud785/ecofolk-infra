# modules/idle_sit_sweep (ecofolk-infra#17, cloud part of ecofolk#460)

One Cloud Scheduler job, `idle-sit-sweep`, that POSTs `{api_url}/internal/sweep-idle-sits` so the API
closes idle sits. Terraform half only; the endpoint itself is ecofolk#460.

| input | default | dev (`environments/dev`) |
| --- | --- | --- |
| `sweep_schedule` (America/Chicago) | `0 */2 * * *` (every 2 hours, under the 3h threshold) | `0 5-21/2 * * *` |
| `api_url` | none | `module.cloudrun_api.uri` |

- **Dev skips the night.** #14 stops dev Cloud SQL from 22:15 to 04:45 CT, so an overnight sweep would
  fail to reach the database and page through #24's alert. Dev's sweeps run 05:00 to 21:00, every
  2 hours. A sit left idle overnight still closes correctly at the first morning sweep: ecofolk#460 sets
  `ended_at` to the last activity, not to the sweep's run time.

## The credential: set out of band, never in Terraform

The API checks the sweep request for `Authorization: Bearer <SWEEP_TOKEN>`. Terraform doesn't write
that header, and the job carries no Google token:

- **No header value in Terraform.** A Scheduler `http_target` header is a literal stored in the job;
  Scheduler can't resolve a Secret Manager reference at call time. Setting the value here would put
  `SWEEP_TOKEN` in source or state, and C7 forbids `google_secret_manager_secret_version` anyway.
  The header is set by hand after the first apply, and `lifecycle { ignore_changes =
  [http_target[0].headers] }` keeps every later apply from removing it.
- **No `oidc_token` and no `oauth_token`.** A Scheduler token also writes `Authorization`, so it would
  collide with the bearer token and the sweep would 401. The API service is public (it serves the web
  client), so a Google-signed token adds nothing. With no token there's no service account to run as,
  and no IAM binding for this job.

`tests/idle_sit_sweep.tftest.hcl` asserts that no `.tf` file in this module mentions `SWEEP_TOKEN` or
`Authorization`.

## LOCAL FOLLOW-UP (ecofolk#460 / L1(a))

After the first apply, set the header. The value comes from 1Password, piped in, never echoed and
never typed into shell history (the Architect's shape on #17; the exact pipe is the local session's):

```bash
gcloud scheduler jobs update http idle-sit-sweep --project=ecofolk-dev \
  --location=northamerica-northeast1 --update-headers=Authorization=Bearer\ <value>
```

Then check that a later `terraform apply` leaves the header in place (`ignore_changes`), and whether
the refreshed state now holds it: the Scheduler API may return header values on read, which the
provider would record in state.

Also add the ef#395 inventory line.

## Read-back

Named fields only, never the whole job, and never `httpTarget.headers` (it holds the token):

```bash
gcloud scheduler jobs describe idle-sit-sweep --project=ecofolk-dev \
  --location=northamerica-northeast1 \
  --format="value(name,schedule,timeZone,state,httpTarget.httpMethod,httpTarget.uri)"
```
