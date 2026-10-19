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
| [Restore](#3-restore-from-the-nightly-export) | drafted, with commands from ecofolk-infra#2 and ecofolk-infra#3 |
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
| Database | `modules/cloudsql/` | Postgres 16 instance `ecofolk-pg`, database `ecofolk`; ENTERPRISE, `db-f1-micro`, ZONAL; **private IP only**; automated backups on; IAM DB auth on; `deletion_protection` true (Terraform and GCP side). Maintenance Sunday 05:00 CT, backup 05:30 CT, PITR 7 days; nightly export at 05:15 CT to `<project-id>-sql-exports` (ecofolk-infra#2, `export.tf`). `postgis` and `vector` are created by the app's migrations, not here. |
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

What runs, all on `main`:

- **The export** (ecofolk-infra#2, `modules/cloudsql/export.tf`): Cloud Scheduler job
  `ecofolk-pg-nightly-export` runs at 05:15 America/Chicago and writes the `ecofolk` database to
  `gs://<project-id>-sql-exports/ecofolk.sql.gz`. Every night overwrites the same object. The bucket is
  versioned, so earlier nights are noncurrent versions of it, deleted after 30 days.
- **The restore** (ecofolk-infra#3, `scripts/restore-from-export.sh`): creates database `ecofolk` on a
  target instance, imports the export, checks `postgis` and `vector`, and prints three tables' row counts.
  It does **not** create or delete the target instance, and it does not compare counts: you do both
  (steps 2, 4 and 6 below). Its tests are `scripts/tests/test_restore_from_export.sh`, run against a
  stubbed `gcloud` only.

Run every command below from a clone of this repo, in one shell, after setting the project for that
shell only (the script uses gcloud's own project):

```bash
export CLOUDSDK_CORE_PROJECT=<project-id>
```

### 3.1 Before you start

- [ ] ecofolk-infra#2 and ecofolk-infra#3 are merged **and applied** (both are on `main`), and the
      export's LOCAL FOLLOW-UP L1(a) is done: the `ops-scheduler` service account and the bindings listed
      in `modules/cloudsql/export.tf`. Without them the export job fails and no export exists.
- [ ] The restore's own LOCAL FOLLOW-UP items (header of `scripts/restore-from-export.sh`) are done: read
      on the export bucket for the instance's service account, and Cloud SQL rights for you.
- [ ] You have a local session with your own credentials for `<project-id>`.
- [ ] You've picked a **new** target instance name, `<target-instance>`, different from `ecofolk-pg`.
      Never restore over the live instance in a rehearsal. (The script refuses `ecofolk-pg` and exits 2.)
- [ ] You've picked the **three tables** to count rows in (`<table1>` `<table2>` `<table3>`, plain
      lower-case identifiers, optionally `schema.table`), and you know their expected counts as of the
      export. The script takes the names as arguments; the counts are yours to compare.

### 3.2 Steps

1. **Pick the export.** First confirm the last nightly exports succeeded: they show as `EXPORT`
   operations on the live instance.

   ```bash
   gcloud sql operations list --instance=ecofolk-pg \
     --filter="operationType=EXPORT" --limit=3 \
     --format="table(endTime,status,error.errors[0].code)"
   ```

   Expected: the newest row is from today's (or the last) 05:15 CT run, `status` `DONE`, no error code.
   If the newest run failed, the current object is an older night: check its timestamp below.

   Then list the export object's versions with their times:

   ```bash
   gcloud storage ls --all-versions --long gs://<project-id>-sql-exports/ecofolk.sql.gz
   ```

   Expected: one line per kept night, each `<size> <time> gs://<project-id>-sql-exports/ecofolk.sql.gz#<generation>`.
   The newest line is the live object. Record its time in §3.3 as the export timestamp: it's the restore
   point.

   - **Restoring the latest night (the normal case):** `<export-uri>` is
     `gs://<project-id>-sql-exports/ecofolk.sql.gz`.
   - **Restoring an earlier night** (the latest is bad): copy that version to its own object first, and
     use the copy as `<export-uri>`. The copy is deleted by the bucket's 30-day rule like any export.

     ```bash
     gcloud storage cp \
       "gs://<project-id>-sql-exports/ecofolk.sql.gz#<generation>" \
       gs://<project-id>-sql-exports/restore/ecofolk-<yyyymmdd>.sql.gz
     ```

2. **Create the fresh target instance.** It mirrors `ecofolk-pg` (`modules/cloudsql/main.tf`): Postgres 16,
   ENTERPRISE, `db-f1-micro`, ZONAL, private IP only on the `ecofolk` VPC (`modules/network/`), IAM
   database auth on, in Montréal. Two deliberate differences: it has the Cloud SQL **Data API** allowed,
   because the script runs its checks through `gcloud sql instances execute-sql`, and it has no deletion
   protection, so step 6 can remove it.

   ```bash
   gcloud sql instances create <target-instance> \
     --region=northamerica-northeast1 \
     --database-version=POSTGRES_16 --edition=enterprise --tier=db-f1-micro \
     --availability-type=zonal \
     --no-assign-ip --network=ecofolk \
     --database-flags=cloudsql.iam_authentication=on \
     --data-api-access=ALLOW_DATA_API
   ```

   Expected: gcloud waits, then lists the new instance with `STATUS` `RUNNABLE`. Record "Target instance
   ready" in §3.3.

   Confirm the target reads the export as the same service account the export bucket was granted to
   (Cloud SQL uses one service account per project). This compares the two without printing either
   address:

   ```bash
   [ "$(gcloud sql instances describe ecofolk-pg --format='value(serviceAccountEmailAddress)')" = \
     "$(gcloud sql instances describe <target-instance> --format='value(serviceAccountEmailAddress)')" ] \
     && echo "same service account" || echo "DIFFERENT: stop, the import can't read the bucket"
   ```

   Then add yourself as an IAM database user on the target: `execute-sql` connects as your Google
   account, so a database user with that name must exist.

   ```bash
   gcloud sql users create <your-google-account-email> \
     --instance=<target-instance> --type=CLOUD_IAM_USER \
     --database-roles=cloudsqlsuperuser
   ```

   `cloudsqlsuperuser` is there so your user can count rows in tables the import created under another
   owner. This is a throwaway rehearsal instance; never do this on `ecofolk-pg`. Whether that role is
   enough for every restored table is unverified until the first performance: if step 4 fails with
   "could not count rows", note it under **Performed** and raise it on ecofolk#405.

3. **Run the restore** into `<target-instance>`:

   ```bash
   bash scripts/restore-from-export.sh <export-uri> <target-instance> <table1> <table2> <table3>; \
     echo "exit=$?"
   ```

   It runs four stages in order and stops at the first failure:

   ```text
   == restore <export-uri> -> <target-instance> (database ecofolk)
   -- 1/4 create database
   -- 2/4 import
   -- 3/4 extensions
   ok  extension postgis
   ok  extension vector
   -- 4/4 tables
   ok  table <table1> rows=<n>
   ok  table <table2> rows=<n>
   ok  table <table3> rows=<n>
   RESTORE_OK: <target-instance> database ecofolk has postgis and vector, and all 3 tables.
   exit=0
   ```

   (gcloud's own progress lines for the create and the import appear between these.) Record "Import
   finished" in §3.3 when `-- 3/4 extensions` prints.

   **Extension check (the step that matters).** The restore passes only if **both** `postgis` **and**
   `vector` exist in the restored database. One of the two isn't enough: ef#455 found a check that
   passed with only one. The script checks each on its own and prints `ok  extension <name>` for each.
   The app's migrations create both (`modules/cloudsql/` header), so a restore that lacks either one is
   broken, whatever the row counts say. A miss reads:

   ```text
   RESTORE_FAILED: extension vector is missing from ecofolk on <target-instance>
   ```

4. **Row counts.** Compare each `ok  table <name> rows=<n>` line against the count you expected as of the
   export timestamp, and record each in §3.3. The script only proves each table exists and is countable;
   the comparison is yours. A table that doesn't exist reads
   `RESTORE_FAILED: table <name> is missing from ecofolk on <target-instance>`.

5. **Exit status.** The `exit=` line printed straight after the script (step 3's command).
   Expected: `exit=0` with `RESTORE_OK` printed. `exit=1` is a failed restore (the `RESTORE_FAILED:` line
   names the step); `exit=2` is bad arguments, and nothing ran. Record anything other than 0 as a failed
   restore.

6. **Clean up the rehearsal instance** if this was a rehearsal, so it doesn't bill while idle. The script
   never deletes anything; you do.

   ```bash
   gcloud sql instances delete <target-instance>
   ```

   gcloud asks you to confirm. If step 1 made a copy under `restore/`, remove it too:

   ```bash
   gcloud storage rm gs://<project-id>-sql-exports/restore/ecofolk-<yyyymmdd>.sql.gz
   ```

   Then end the shell, or `unset CLOUDSDK_CORE_PROJECT`.

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
