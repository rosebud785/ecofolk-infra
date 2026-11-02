# Go-live checklist: qa, then prod

ecofolk-infra#146. Every `LOCAL FOLLOW-UP` and every `TODO(go-live)` comment on `main`, put in order per
environment, plus the go-live items the issue names that have no comment of their own (billing, DNS,
email-enumeration protection, OAuth providers, TLS to Cloud SQL).

This doc lists steps. It does not do or decide any of them. Anything marked **Andy** is Andy's call and is
left blank here, on purpose.

## How to read it

- **Order.** Do the rows of a table top to bottom. A row that depends on another names it.
- **Source.** `file:line` of the comment on `main`, or the issue. Line numbers drift; re-run the grep below.
- **Who.**
  - **Andy**: the owner. Accounts, billing, decisions, spend, and the 1Password items.
  - **Deployer**: runs `terraform plan`/`apply` from `main` (README: *Plan and apply*) and the ecofolk#408
    deploy.
  - **local coder**: a local session with its own credentials. Writes and runs the out-of-band pastes: IAM,
    DB users, secret versions, settings not in the provider's schema (CONTRIBUTING: *No IAM*).
- **Needs.** An account, a billing link, a 1Password item, or another row. 1Password items are named by
  what they hold; no item name is recorded in this public repo, so the row says which value, not where.
- **Verify.** A read-back you can run. `<project>`, `<bucket>`, `<api-host>` and the like are placeholders; `<region>` is the pinned `northamerica-northeast1`.
  Read-backs print named fields only. Never paste their output into an issue or PR if it carries an
  address.
- **Never** write a secret value, token, account ID, email or IP address into this doc, an issue or a PR.

## The grep

The source list is this, from the repo root on an up-to-date `main` (this doc is excluded, because it
quotes the markers):

```bash
git grep -n -E 'LOCAL FOLLOW-UP|TODO\(go-live\)' -- ':!docs/go-live-checklist.md' | cut -d: -f1,2
```

On `main` at the time of writing it prints **53** lines. Each appears **exactly once** in the
[Source index](#source-index) below, which says where it went: a qa row, a prod row, the dev-only list, or
"reference" (the line mentions a follow-up but is not one).

To check the index still matches the grep (no output means it matches):

```bash
diff \
  <(git grep -n -E 'LOCAL FOLLOW-UP|TODO\(go-live\)' -- ':!docs/go-live-checklist.md' | cut -d: -f1,2) \
  <(sed -n '/^## Source index/,/^## /p' docs/go-live-checklist.md | grep -oE '^\| `[^`]+`' | tr -d '|` ')
```

If it prints anything, a comment was added, removed or moved: update the index and the table row it feeds.

Named follow-up tags and where they land: **L-RUN** (Q1, Q4, Q10, P7, P15, P22), **L-SQL** (Q2, P14),
**L-ALERT** (P9), **L-AUTH** (Q8, P20; tagged `L-AUTH` in `modules/auth`, not `LOCAL FOLLOW-UP`, so the grep
does not print it), **L1(a)** (P8, P13), **L1(b)** (dev only). **L-R2PIN**: no comment on `main` carries it;
media moved from R2 to GCS (ef#926), so there is nothing to pin.

---

## qa

QA is a namespace inside `ecofolk-dev`, not a project (#13). It reuses dev's VPC, Cloud SQL instance, media
bucket, runtime service account and Auth config, so several qa rows are dev-project prerequisites. Dev is
already applied by CI (`infra-apply.yml`); `environments/qa` is applied only from `main` by the Deployer.

| # | Step | Source | Who | Needs | Verify |
| - | - | - | - | - | - |
| Q1 | Dev's API runtime service account (`var.api_service_account_id`) exists with **no roles**, and tf-apply holds `roles/iam.serviceAccountUser` on that one SA only (L-RUN items 1–2). QA runs as this SA. | `environments/dev/main.tf:141` | local coder | Local credentials on `ecofolk-dev` | `gcloud iam service-accounts list --project=ecofolk-dev --format='value(name)'` lists it; `gcloud iam service-accounts get-iam-policy <api-sa> --project=ecofolk-dev --format='value(bindings.role)'` shows `roles/iam.serviceAccountUser` |
| Q2 | Create QA's built-in Postgres user (`db_user_name` output, `ecofolk_qa_app`) on dev's instance, password out of band, and give it ownership of `ecofolk_qa` only (L-SQL). Not IAM. | `environments/qa/main.tf:27`, `modules/sql_database/main.tf:17` | local coder | The `ecofolk_qa` database (Q3's apply creates it); a 1Password item for the QA DB password (Andy) | `gcloud sql users list --instance=ecofolk-pg --project=ecofolk-dev --format='value(name)'` includes `ecofolk_qa_app` |
| Q3 | First plan/apply of `environments/qa` from `main` (state prefix `qa` in dev's state bucket). | `environments/qa/main.tf:21` (comment, not a marker) | Deployer | Q1 | `terraform -chdir=environments/qa output database_name` prints `ecofolk_qa`; `output api_uri` prints a run.app URI |
| Q4 | `roles/storage.objectAdmin` for dev's runtime SA on dev's media bucket only. QA writes under `qa/` in that bucket as the same SA (L-RUN, ecofolk#890). | `environments/dev/main.tf:294` | local coder | Q1 | `gcloud storage buckets get-iam-policy gs://ecofolk-dev-media --format='value(bindings.role)'` includes `roles/storage.objectAdmin` |
| Q5 | Dev's secret VALUES: one version per container (ecofolk#936), then `roles/secretmanager.secretAccessor` for the runtime SA on each named secret only (L-RUN, ecofolk#890). QA's service takes no `secret_env` today; these are the project's secrets QA would read. | `environments/dev/main.tf:266`, `environments/dev/main.tf:268` | Andy (values), local coder (versions, grants) | A 1Password item per secret name (`modules/secrets/variables.tf` lists the names) | `gcloud secrets versions list <SECRET_NAME> --project=ecofolk-dev --format='value(name,state)'` shows one `ENABLED`; never `access` a version to check it |
| Q6 | `roles/cloudsql.client` for dev's runtime SA (L-RUN item 3, ef#399), before QA's API connects to dev's instance. | `environments/dev/main.tf:141` (item 3) | local coder | Q1 | `gcloud projects get-iam-policy ecofolk-dev --flatten='bindings[].members' --filter='bindings.role=roles/cloudsql.client' --format='value(bindings.role)'` is non-empty |
| Q7 | Email-enumeration protection on (`emailPrivacyConfig.enableImprovedEmailPrivacy`), set out of band: not in the provider's schema. Project-level, so QA shares dev's. | ecofolk#786; `modules/auth/README.md` (*Set out of band*) | local coder | Local credentials on `ecofolk-dev` | GET `https://identitytoolkit.googleapis.com/admin/v2/projects/ecofolk-dev/config` with a bearer token and print only `.emailPrivacyConfig.enableImprovedEmailPrivacy` (jq): `true` |
| Q8 | OAuth providers (Google, then Apple, Facebook) alongside email/password, applied from `local-only/` or by hand (L-AUTH). Each client secret lives in Secret Manager, never in Terraform. | `modules/auth/main.tf:10`; `modules/auth/README.md` (*Sign-in providers*) | Andy (developer accounts, OAuth clients), local coder (IdP config) | Google OAuth client; Apple and Facebook developer accounts; a 1Password item per client secret | Firebase console, Authentication → Sign-in method lists each provider enabled; `modules/auth` tests still pass (no IdP resource in the repo) |
| Q9 | TLS to Cloud SQL: confirm the API's DB driver connects over TLS (app side), **then** an infra PR sets `ssl_mode = "ENCRYPTED_ONLY"` in `modules/cloudsql` with a test and drops the `GCP-0015` line from `.trivyignore`, then the apply. Never apply before the app side is confirmed: it breaks the API's DB connection. QA shares dev's instance. | #87, ecofolk#1183; `.trivyignore` (GCP-0015) | local coder (app check, PR), Deployer (apply) | The app repo's DB TLS setting | `gcloud sql instances describe ecofolk-pg --project=ecofolk-dev --format='value(settings.ipConfiguration.sslMode)'` prints `ENCRYPTED_ONLY`; the API's `/health` still returns 200 |
| Q10 | First real QA deploy (ef#408): `allUsers` → `roles/run.invoker` on `ecofolk-api-qa`, and the deploy sets the service's database, user and media prefix from `environments/qa` outputs (L-RUN). | `environments/qa/main.tf:29` | Deployer (deploy), local coder (invoker binding) | Q2–Q6; the real image | `gcloud run services get-iam-policy ecofolk-api-qa --region=<region> --project=ecofolk-dev --format='value(bindings.role)'` includes `roles/run.invoker`; an unauthenticated `curl -fsS https://<qa-api-host>/health` returns 200 |

---

## prod

`ecofolk-prod` stays unlinked from billing until go-live, and no workflow plans or applies
`environments/prod` (`ci.yml` only validates it; `scripts/check-workflows.sh` rule 5).

| # | Step | Source | Who | Needs | Verify |
| - | - | - | - | - | - |
| P1 | DNS and registrar: fill `docs/dns-and-certs.md` §4 (domain name, registrar A or B, API path 2.2a or 2.2b). It is blank on purpose. The prod web host (`var.web_host`, no default) follows from it. | `docs/dns-and-certs.md` §4; ecofolk#670; `environments/prod/variables.tf:19` | **Andy** | The registrar account; the domain | §4's table has a Choice, Decided by and Date in every row |
| P2 | Link billing to `ecofolk-prod`. | issue #146; `README.md:50` | **Andy** | The billing account | `gcloud billing projects describe ecofolk-prod --format='value(billingEnabled)'` prints `True` |
| P3 | Name the prod apply route: who runs it, from where, as which identity. No workflow applies prod, and nothing on `main` says who does. | `environments/prod/main.tf:4` (comment, not a marker); `scripts/check-workflows.sh` rule 5 | **Andy** | — | The route is written down (an issue or the runbook) before P11 |
| P4 | Create the prod state bucket out of band (Montréal, private, versioned, like dev's). | `environments/prod/main.tf:17` | local coder | P2 | `gcloud storage buckets describe gs://<bucket> --format='value(location,versioning_enabled)'` prints `NORTHAMERICA-NORTHEAST1` and `True` |
| P5 | Infra PR: uncomment the `backend "gcs"` block (prefix `prod`) in `environments/prod/main.tf`; the bucket is supplied at init, as for dev, never committed. | `environments/prod/main.tf:17` | local coder | P4 | CI `validate` green on the PR; `terraform -chdir=environments/prod init -backend-config="bucket=<bucket>"` succeeds locally |
| P6 | tf-apply gets `roles/compute.networkAdmin` and `roles/servicenetworking.networksAdmin` on `ecofolk-prod` (or a role that includes them) before the first apply. | `modules/network/main.tf:16` | local coder | P2, P3 (which identity) | `gcloud projects get-iam-policy ecofolk-prod --flatten='bindings[].members' --filter='bindings.role:networkAdmin OR bindings.role:networksAdmin' --format='value(bindings.role)'` shows both |
| P7 | Create the API runtime SA (`var.api_service_account_id`) in `ecofolk-prod` with **no roles**; grant tf-apply `roles/iam.serviceAccountUser` on that one SA only (L-RUN items 1–2). Without it the first apply 403s on `actAs` (#19). | `environments/prod/main.tf:87`, `modules/cloudrun_api/main.tf:22` | local coder | P2 | As Q1, with `--project=ecofolk-prod` |
| P8 | Create `ops-scheduler` in `ecofolk-prod` with `roles/cloudsql.viewer` on the project; grant tf-apply `roles/iam.serviceAccountUser` on that one SA (L1(a) items 1–2). | `environments/prod/main.tf:58`, `modules/cloudsql/export.tf:19` | local coder | P2 | `gcloud iam service-accounts get-iam-policy <ops-scheduler-sa> --project=ecofolk-prod --format='value(bindings.role)'` shows `roles/iam.serviceAccountUser` |
| P9 | L-ALERT for prod: the email notification channel, made by hand in `ecofolk-prod`; the two log filters from the app's real log fields (plus a structured log event where a failure isn't logged distinctly). All three reach the prod apply as inputs, never as a committed tfvars. | `modules/monitoring/alerts.tf:23` | Andy (channel), local coder (filters) | The alert address (Andy's; never in this repo) | `gcloud beta monitoring channels list --project=ecofolk-prod --format='value(name,type)'` shows one `email` channel; the prod plan shows both log-based metrics with non-empty filters |
| P10 | Confirm the prod Cloud SQL tier (cost review). Not a grep hit: the comment reads `go-live:`, not `TODO(go-live)`. | `environments/prod/main.tf:66` | **Andy** | `docs/cost-model.md` | The comment is resolved in a PR (tier kept or changed) |
| P11 | First prod plan, then apply, from `main`, by P3's route. | issue #12; `README.md` (*Plan and apply*) | Deployer | P1 (`web_host`), P3–P10 | The apply ends clean; `terraform -chdir=environments/prod output sql_connection_name` prints a value |
| P12 | Conditional: if the first apply 403s on Cloud SQL (`cloudsql.instances.*`), it goes to the Architect and the narrowest role is added locally; if it 403s on `identitytoolkit.config.*`, add `roles/identitytoolkit.admin` on the project. Nothing to do if no 403. | `modules/cloudsql/main.tf:21`, `modules/auth/main.tf:16` | local coder | P11's result | Re-run of the apply ends clean |
| P13 | Grant the prod Cloud SQL instance's own service account (output `instance_service_account_email`) `roles/storage.objectAdmin` on `ecofolk-prod-sql-exports` only (L1(a) item 3), **before** the 05:15 CT export job's first run (runbook §5). | `modules/cloudsql/export.tf:19` (item 3) | local coder | P11 | `gcloud storage buckets get-iam-policy gs://ecofolk-prod-sql-exports --format='value(bindings.role)'` includes `roles/storage.objectAdmin`; check the grant, not the plan |
| P14 | L-SQL for prod: the app's DB user (password into Secret Manager, never Terraform), and the IAM DB user for the runtime SA with `roles/cloudsql.client` and `roles/cloudsql.instanceUser` on the project. | `modules/cloudsql/main.tf:24` | local coder | P7, P11; a 1Password item for the prod DB password (Andy) | `gcloud sql users list --instance=ecofolk-pg --project=ecofolk-prod --format='value(name,type)'` shows both users |
| P15 | `roles/storage.objectAdmin` for the API runtime SA on the prod media bucket only (L-RUN, ecofolk#890). No HMAC key. | `environments/prod/main.tf:114`, `modules/media_bucket/main.tf:19` | local coder | P7, P11 | `gcloud storage buckets get-iam-policy gs://ecofolk-prod-media --format='value(bindings.role)'` includes `roles/storage.objectAdmin` |
| P16 | `roles/artifactregistry.writer` on `ecofolk-images` for the image-push identity, and `roles/artifactregistry.reader` on it for the Cloud Run service agent. | `modules/artifact_registry/main.tf:14` | local coder | P11 | `gcloud artifacts repositories get-iam-policy ecofolk-images --location=<region> --project=ecofolk-prod --format='value(bindings.role)'` shows both roles |
| P17 | Prod composition gap: `environments/prod` does not call `modules/secrets`, `modules/web_hosting`, `modules/migrate_job`, `modules/idle_sit_sweep` or `modules/sync_usgs_water`, which dev does. Whether prod gains them before go-live is not decided on `main`. | `environments/prod/main.tf:8` (comment, not a marker) | **Andy** (with the Architect) | — | An issue records the decision; if yes, an infra PR adds them and P18 follows |
| P18 | Prod secret VALUES (ecofolk#936): one version per container, then `roles/secretmanager.secretAccessor` for the runtime SA on each named secret only (L-RUN, ecofolk#890). Blocked: prod has no secret containers until P17 adds `modules/secrets`. | `modules/secrets/main.tf:16`, `modules/secrets/main.tf:18` | Andy (values), local coder (versions, grants) | P17; a 1Password item per secret name | As Q5, with `--project=ecofolk-prod` |
| P19 | Email-enumeration protection on in `ecofolk-prod`, right after the first `modules/auth` apply. | ecofolk#786 | local coder | P11 | As Q7, for `ecofolk-prod` |
| P20 | OAuth providers in `ecofolk-prod` (L-AUTH), as Q8. | `modules/auth/main.tf:10` | Andy (accounts, OAuth clients), local coder (IdP config) | Q8's accounts; prod redirect URIs from P1's domain | As Q8, in the prod project |
| P21 | TLS to Cloud SQL on the prod instance. Q9's module change covers prod too; confirm the prod API's DB connection is TLS before the prod apply that carries it. | #87, ecofolk#1183 | Deployer | Q9 | As Q9, with `--project=ecofolk-prod` |
| P22 | First real prod deploy (ef#408): `allUsers` → `roles/run.invoker` on the prod API service, and `roles/cloudsql.client` for the runtime SA (ef#399) (L-RUN "later" items). | `environments/prod/main.tf:87` (later items) | Deployer (deploy), local coder (bindings) | P11–P21 | As Q10, for the prod service; unauthenticated `curl -fsS https://<api-host>/health` returns 200; the uptime checks go green |

---

## Dev only (not a qa or prod step)

These hits are in modules or blocks only `environments/dev` calls (`environments/prod/main.tf:11`: dev-only
modules refuse a `*-prod` project). They are listed so the grep count adds up. If P17 brings a module to
prod, its follow-up becomes a prod row.

| Hit | What | Why not qa/prod |
| - | - | - |
| `environments/dev/main.tf:64` | Artifact Registry writer/reader on dev's repo (ecofolk#1109) | Dev's repo; prod's is P16 |
| `environments/dev/main.tf:82` | `ops-scheduler` and its bindings in dev (L1(a)) | Dev's; prod's is P8 |
| `environments/dev/main.tf:102`, `modules/sql_off_hours/main.tf:25`, `modules/sql_off_hours/README.md:23` | `ops-scheduler` gets `roles/cloudsql.editor` on `ecofolk-dev` for the off-hours stop | Dev only, never prod (#14) |
| `environments/dev/main.tf:187`, `modules/migrate_job/main.tf:19` | Migrate job SA and grants (ecofolk#1169) | Not in the prod root (P17) |
| `environments/dev/main.tf:228`, `modules/idle_sit_sweep/main.tf:16`, `modules/idle_sit_sweep/README.md:40` | `sweep-invoker` SA, actAs, ef#395 inventory line | Not in the prod root (P17) |
| `environments/dev/main.tf:249`, `modules/sync_usgs_water/main.tf:16`, `modules/sync_usgs_water/README.md:25` | App side: `/internal/sync-usgs-water` accepts the invoker's email and audience (ecofolk#1092) | Not in the prod root (P17) |
| `environments/dev/main.tf:326`, `modules/billing_killswitch/main.tf:20`, `:22`, `:24`, `modules/billing_killswitch/README.md:55` | Dev budget, kill-switch SA and its grants (L1(b)) | Dev only, never prod (#15) |
| `environments/dev/main.tf:350` | L-ALERT log filters for the dev apply | Dev's; prod's is P9 |
| `modules/web_hosting/main.tf:18` | Conditional 403 role for Firebase Hosting | Not in the prod root (P17) |

---

## Source index

Every line the grep prints, once, in the grep's order.

| Hit | Goes to |
| - | - |
| `CONTRIBUTING.md:14` | reference: the convention itself |
| `docs/runbook.md:322` | reference: restore drill prerequisite, points at L1(a) (P8, P13) |
| `docs/runbook.md:324` | reference: restore drill prerequisite, points at the restore script's list |
| `environments/dev/main.tf:64` | dev only |
| `environments/dev/main.tf:82` | dev only |
| `environments/dev/main.tf:102` | dev only |
| `environments/dev/main.tf:141` | Q1 (items 1–2), Q6 (item 3) |
| `environments/dev/main.tf:187` | dev only |
| `environments/dev/main.tf:228` | dev only |
| `environments/dev/main.tf:249` | dev only |
| `environments/dev/main.tf:266` | Q5 |
| `environments/dev/main.tf:268` | Q5 |
| `environments/dev/main.tf:294` | Q4 |
| `environments/dev/main.tf:326` | dev only |
| `environments/dev/main.tf:350` | dev only |
| `environments/prod/main.tf:17` | P4, P5 |
| `environments/prod/main.tf:58` | P8 |
| `environments/prod/main.tf:87` | P7 (items 1–2), P22 (later items) |
| `environments/prod/main.tf:114` | P15 |
| `environments/qa/main.tf:27` | Q2 |
| `environments/qa/main.tf:29` | Q10 |
| `modules/artifact_registry/main.tf:14` | P16 |
| `modules/auth/main.tf:16` | P12 |
| `modules/billing_killswitch/README.md:55` | dev only |
| `modules/billing_killswitch/main.tf:20` | dev only |
| `modules/billing_killswitch/main.tf:22` | dev only |
| `modules/billing_killswitch/main.tf:24` | dev only |
| `modules/cloudrun_api/main.tf:22` | P7 |
| `modules/cloudsql/README.md:52` | reference: output description, points at L1(a) item 3 (P13) |
| `modules/cloudsql/export.tf:19` | P8 (items 1–2), P13 (item 3) |
| `modules/cloudsql/main.tf:21` | P12 |
| `modules/cloudsql/main.tf:24` | P14 |
| `modules/cloudsql/outputs.tf:23` | reference: output description, points at L1(a) item 3 (P13) |
| `modules/idle_sit_sweep/README.md:40` | dev only |
| `modules/idle_sit_sweep/main.tf:16` | dev only |
| `modules/media_bucket/main.tf:19` | P15 |
| `modules/migrate_job/README.md:10` | reference: points at `modules/migrate_job/main.tf:19` (dev only) |
| `modules/migrate_job/main.tf:19` | dev only |
| `modules/monitoring/alerts.tf:23` | P9 |
| `modules/monitoring/dashboard.tf:23` | reference: says the module is not wired into dev; it is (`environments/dev/main.tf:339`, #90), and prod passes the inputs |
| `modules/monitoring/uptime.tf:15` | reference: same as `dashboard.tf:23`; prod's `web_host` is P1 |
| `modules/network/main.tf:16` | P6 |
| `modules/secrets/main.tf:16` | P18 |
| `modules/secrets/main.tf:18` | P18 |
| `modules/sql_database/README.md:5` | reference: points at L-SQL (Q2) |
| `modules/sql_database/main.tf:17` | Q2 |
| `modules/sql_database/outputs.tf:6` | reference: points at L-SQL (Q2) |
| `modules/sql_off_hours/README.md:23` | dev only |
| `modules/sql_off_hours/main.tf:25` | dev only |
| `modules/sync_usgs_water/README.md:25` | dev only |
| `modules/sync_usgs_water/main.tf:16` | dev only |
| `modules/web_hosting/main.tf:18` | dev only |
| `scripts/restore-from-export.sh:36` | reference: restore drill grants (runbook §3), not a go-live step |
