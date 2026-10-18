# EcoFolk production runbook

**Status: DRAFT (ecofolk-infra#27, Architect re-scope 2026-10-09).** Nothing in this document has been
performed. A runbook nobody has run is still a design doc: each procedure becomes real only when the
local session (ecofolk#405) runs it once and fills in its **Performed** line. Until then, every step
here is a plan.

Scope of this draft:

| Procedure | State |
| - | - |
| [Deploy](#1-deploy) | TBD: ecofolk#408 |
| [Rollback](#2-rollback) | TBD: ecofolk#408 |
| [Restore](#3-restore-from-the-nightly-export) | drafted; its commands wait on ecofolk-infra#2 and ecofolk-infra#3 |
| [Rotate](#4-rotate-a-secret-manager-held-credential) | drafted, generic shape |

Rules for every procedure:

- **No values in this document, ever.** Placeholders are written `<like-this>`. Secret values, tfvars
  values, project numbers and service-account addresses never go in here, in a ticket, or in a
  terminal log you paste anywhere (this repo is public; see [CONTRIBUTING.md](../CONTRIBUTING.md)).
- **Region:** everything regional is `northamerica-northeast1` (Montréal, ef#391). A command that needs a
  region passes it explicitly.
- **Project:** `<project-id>` is the dev project id from the repo variable `GCP_PROJECT_ID`
  (`environments/dev/variables.tf`). `ecofolk-prod` holds only enabled APIs today: the prod
  stack in `environments/prod/main.tf` (#12) is not applied before go-live, and the project stays unlinked
  from billing until then.
- **Credentials:** these procedures run from a local session with a human's own credentials. Nothing
  here runs in CI, and no pull-request path can reach GCP (README).

---

## 0. What this runbook operates (current `main`)

Names below are the module defaults, as instantiated by `environments/dev/main.tf`.

| Component | Module | Name / key facts |
| - | - | - |
| API | `modules/cloudrun_api/` | Cloud Run v2 service `ecofolk-api`; min 0, max 3 instances; public ingress; Direct VPC egress (private ranges only). Terraform ignores image changes: deploys own the image (ecofolk#408). Env vars are non-secret only; Secret Manager refs come with ef#399. |
| Database | `modules/cloudsql/` | Postgres 16 instance `ecofolk-pg`, database `ecofolk`; ENTERPRISE, `db-f1-micro`, ZONAL; **private IP only**; automated backups on; IAM DB auth on; `deletion_protection` true (Terraform and GCP side). No backup window and no PITR yet (ecofolk-infra#2). `postgis` and `vector` are created by the app's migrations, not here. |
| Media | `modules/media_bucket/` | Bucket `<project-id>-media`, location `NORTHAMERICA-NORTHEAST1`; uniform access, public access prevention enforced; **no versioning**; soft delete 7 days; only lifecycle rule aborts incomplete multipart uploads after 1 day. Retention is the app's (ecofolk#310). |
| Network | `modules/network/` | Custom-mode VPC, one subnet in Montréal, a Private Service Access range and peering for Cloud SQL's private IP. No connector, no NAT, no firewall rules. |
| Images | `modules/artifact_registry/` | Docker repository with cleanup (keep 10 most recent, delete untagged after 7 days). **The module exists but no root calls it yet**, so no repository is created by `main` today. |
| Auth | `modules/auth/` | Firebase Auth, email + password only; OAuth providers are local follow-up L-AUTH. |
| DNS and certificates | [docs/dns-and-certs.md](dns-and-certs.md) | Every certificate renews automatically (§3 there). There is **no certificate rotation procedure**: §4 below covers Secret Manager credentials, not TLS. Registrar and API path are still Andy's decision (§4 there). |

### Operating note: API rate limits are per instance

The API's rate-limit store is **per Cloud Run instance** (ef#407 / ecofolk PR #919, 2026-10-09). Each
instance counts on its own, so the effective limit is **up to N× the configured numbers**, where N is
the live instance count:

- dev: N ≤ 3 (`max_instance_count` in `modules/cloudrun_api/`, capped by policy C7);
- prod: N ≤ 5 (the prod cap in `policy/`; no prod Cloud Run service exists yet).

When you read a rate-limit number in an incident, multiply by the instance count at that time before
deciding a limit "didn't work". The configured numbers live in the app repo, not here.

---

## 1. Deploy

**TBD: ecofolk#408.** The deploy pipeline doesn't exist yet. Left empty on purpose.

## 2. Rollback

**TBD: ecofolk#408.** Depends on the deploy pipeline. Left empty on purpose.

---

## 3. Restore from the nightly export

**Goal:** bring the database back from a nightly export into a **fresh** Cloud SQL instance, then prove
the restore is usable: both extensions present and expected rows in place.

**Why the export and not the automated backups:** `modules/cloudsql/` has automated backups on, but
automated backups are deleted along with the instance. The nightly export to GCS is the copy that
outlives it (ecofolk-infra#2).

> **Blocked for commands.** Neither piece this procedure runs exists on `main` yet:
>
> - the nightly export (export bucket and scheduler job) is ecofolk-infra#2, open;
> - `scripts/restore-from-export.sh` is ecofolk-infra#3, open.
>
> So this draft gives the steps, the checks and the timings to record, but no commands and no expected
> output. Both are filled in from the merged code when #2 and #3 land, not guessed now.

### 3.1 Before you start

- [ ] ecofolk-infra#2 and ecofolk-infra#3 are merged and applied. (If not, stop: this procedure can't run.)
- [ ] You have a local session with your own credentials for `<project-id>`.
- [ ] You know which export you're restoring: its object URI, `<export-uri>`, and its timestamp.
- [ ] You've picked a **new** target instance name, `<target-instance>`, different from `ecofolk-pg`.
      Never restore over the live instance in a rehearsal.
- [ ] You've picked the **three tables** to count rows in, and you know their expected counts as of
      the export (the script takes the table names as arguments, per ecofolk-infra#3's spec).

### 3.2 Steps

1. **Pick the export.** Find the most recent export object in the export bucket and note its URI and age.
   _Command: TBD with ecofolk-infra#2 (bucket name and object layout)._
2. **Run the restore** into `<target-instance>`. The script creates the target database, imports the
   export, runs the checks in step 3, and exits non-zero on any miss.
   _Command and expected output: TBD with ecofolk-infra#3 (`scripts/restore-from-export.sh`)._
3. **Extension check (the step that matters).** The restore passes only if **both** `postgis` **and**
   `vector` exist in the restored database. One of the two isn't enough: ef#455 found a check that
   passed with only one. The app's migrations create both (`modules/cloudsql/` header), so a restore
   that lacks either one is broken, whatever the row counts say.
4. **Row counts.** The three named tables return their expected counts.
5. **Exit status.** The script exits 0. Any non-zero exit is a failed restore: record it as such.
6. **Clean up the rehearsal instance** if this was a rehearsal, so it doesn't bill while idle.
   _Command: TBD with ecofolk-infra#3 (whether the script or the operator removes it)._

### 3.3 Timings to record

Record wall-clock times (with time zone) as you go. Restore time is the number the Architect needs.

| Mark | Time | Notes |
| - | - | - |
| Export object timestamp (from step 1) | | the restore point: data after this is lost |
| Start (step 2 begins) | | |
| Target instance ready | | |
| Import finished | | |
| Extension check passed | | both `postgis` and `vector` |
| Row counts passed | | table → count |
| End (script exits) | | exit status |
| **Total restore time** (start → end) | | |
| **Data loss window** (export timestamp → incident or start) | | |

### 3.4 Performed

**Performed: <date> by <who>, result**

---

## 4. Rotate a Secret Manager-held credential

**Goal:** replace one credential held in Secret Manager without downtime: add a new version, move the
consumer onto it, then disable the old version. Values are **never** displayed, echoed, logged or
pasted.

This is the generic shape. No secret exists on `main` yet. The secrets themselves, their accessor
bindings and the API's `secret_key_ref` wiring are ef#399 (local). Fill in the specifics per
secret when ef#399 lands.

Placeholders: `<secret-id>` (the Secret Manager secret), `<ENV_NAME>` (the env var the API reads it
as), `<old-version>` and `<new-version>` (version numbers).

### 4.1 Before you start

- [ ] Secret Manager is enabled on the project. **It isn't on `main` today:**
      `secretmanager.googleapis.com` isn't in `modules/project/`'s `enabled_apis`. That's ef#399.
- [ ] The secret exists, with replication pinned to `northamerica-northeast1` (set when the secret is
      created, ef#399, not at rotation).
- [ ] The consumer is the API, Cloud Run service `ecofolk-api` (`modules/cloudrun_api/`), and you know
      which `<ENV_NAME>` and version it references today.
- [ ] You have the new credential from its issuer, and you can revoke the old one there after step 5.

### 4.2 Steps

1. **Note the current state.** List versions and confirm which one is enabled and in use.

   ```bash
   gcloud secrets versions list <secret-id> --project=<project-id>
   ```

   Expected: `<old-version>` is `enabled`. Record its number.

2. **Add the new version without displaying the value or writing it to disk.** Pipe it from your
   password manager straight into `gcloud` on stdin. Never put the value on the command line, since it
   would land in shell history, and don't stage it in a file: `shred` isn't on stock macOS and doesn't
   securely erase on APFS or SSD anyway.

   ```bash
   op read --no-newline "op://<vault>/<item>/<field>" | \
     gcloud secrets versions add <secret-id> --data-file=- --project=<project-id>
   ```

   `--no-newline` matters: without it the stored secret ends in a newline.

   Expected: gcloud reports the new version number. Record it as `<new-version>`. Don't run
   `gcloud secrets versions access`: it prints the value.

3. **Roll the consumer** onto the new version. This creates a new Cloud Run revision that reads it.

   ```bash
   gcloud run services update ecofolk-api \
     --region=northamerica-northeast1 --project=<project-id> \
     --update-secrets=<ENV_NAME>=<secret-id>:<new-version>
   ```

   ⚠️ Drift: if ef#399 puts the secret reference in Terraform (`modules/cloudrun_api/`), a command-line
   update drifts from the code, and the next apply from `main` reverts it. In that case the roll is a
   Terraform change merged to `main`, and this step becomes "merge and apply". Decide which when ef#399
   lands, and rewrite this step to match.

4. **Verify the consumer.** The new revision is ready and serving, and the API answers.

   ```bash
   gcloud run services describe ecofolk-api \
     --region=northamerica-northeast1 --project=<project-id> \
     --format='value(status.latestReadyRevisionName,status.traffic)'
   ```

   Expected: the latest ready revision is the one step 3 created, at 100% traffic. Then exercise the
   path that uses the credential and check it works. (The `/health` endpoint is named in
   [docs/dns-and-certs.md](dns-and-certs.md) §3; whether it touches this credential depends on the
   secret.)

5. **Disable the old version.** Disable it rather than destroy it, so you can undo this step.

   ```bash
   gcloud secrets versions disable <old-version> --secret=<secret-id> --project=<project-id>
   ```

   Expected: `versions list` shows `<new-version>` enabled and `<old-version>` disabled. Then revoke
   the old credential at its issuer.

**Undo, if step 4 fails:** point the consumer back with step 3 using `<old-version>`. If you already
disabled it, re-enable it first:

```bash
gcloud secrets versions enable <old-version> --secret=<secret-id> --project=<project-id>
```

### 4.3 Timings to record

| Mark | Time | Notes |
| - | - | - |
| New version added | | `<new-version>` |
| Consumer revision ready | | revision name |
| Credential path verified | | how |
| Old version disabled | | `<old-version>` |
| Old credential revoked at issuer | | |

### 4.4 Performed

**Performed: <date> by <who>, result**
