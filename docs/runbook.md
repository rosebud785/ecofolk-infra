# EcoFolk production runbook

**Status: DRAFT (ecofolk-infra#27, Architect re-scope 2026-10-09).** Nothing in this document has been
performed. A runbook nobody has run is still a design doc: each procedure becomes real only when the
local session (ecofolk#405) runs it once and fills in its **Performed** line. Until then, every step
here is a plan.

Scope of this draft:

| Procedure | State |
| - | - |
| [Deploy](#1-deploy) | drafted from ecofolk#408's `deploy-dev.sh` (PR ecofolk#1111); never run |
| [Rollback](#2-rollback) | drafted, from gcloud/Firebase docs; never run |
| [Restore](#3-restore-from-the-nightly-export) | drafted, with commands from ecofolk-infra#2 and ecofolk-infra#3 |
| [Rotate](#4-rotate-a-secret-manager-held-credential) | drafted, generic shape |
| [Go-live checklist](#5-go-live-checklist) | ordering rules only; grows as go-live steps are learned |

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

**State: DRAFT, never run.** The script is `scripts/deploy/deploy-dev.sh` in the app repo (ecofolk#408, PR
ecofolk#1111, Architect's ruling (c)). It is a **local** pipeline: no GitHub workflow holds a cloud identity
(ecofolk#883), so a human runs it from their own shell in an **announced deploy slot**. Nothing is observed
yet: the first real run fills in §1.4. Items marked *(unobserved)* come from documentation or the script's
own comments, not from a run on this stack.

What the script does, in order:

1. Refuses a dirty tree, or a `HEAD` that is not `origin/main` after a fetch. Only the main tip deploys.
2. **Test gate.** It finds the one merged PR whose merge commit is `HEAD` and requires every **required**
   check of main's branch protection to be `success` on that PR's head. `skipped`, missing or unreadable
   is a refusal. It makes no gcloud, firebase or docker call before this gate passes.
3. Builds the API image `linux/amd64`, tags it with the sha, pushes it, resolves the registry digest and runs
   `gcloud run deploy ecofolk-api --image <repo>@sha256:<digest>`. **By digest, never by tag.** It passes no
   `--set-env-vars`, `--set-secrets`, `--update-*` or `--service-account`: env, secrets and the runtime
   service account are Terraform's (this repo). Terraform ignores image changes, so the two do not fight.
4. `firebase deploy --only hosting` from `packages/web`.
5. A read-only smoke: the new revision is the latest Ready one and holds 100% of traffic with the pushed
   digest; `/health` is ok; `/version` reports this sha; the startup log shows the server listening (so
   the boot-time config guard passed); the web root serves. It prints revision, digest and web version
   **names only**.

### 1.1 Before the slot

The slot is announced and run by Andy (the impersonator, §1.2). It happens only after **all** of these, in
this order:

- [ ] **Kill-switch reads ARMED** (ef#885, L-slot rev 3.1).
- [ ] **infra#117** applied (internal OIDC env and the shared `run.app` base URL).
- [ ] **ef#1108** merged (one OIDC verifier on `/internal`; `SWEEP_TOKEN` deleted).
- [ ] **infra#66** merged (Cloud Run `secretKeyRef` env mapping). Applied before the slot or in it, per the
      announcement.
- [ ] **infra#119** applied (Artifact Registry repo wired into `environments/dev`). Without it the deploy
      has no registry to push to, and the script refuses on an unset `ECOFOLK_AR_REPO`.
- [ ] **ecofolk#1109** done and read back: the keyless `ecofolk-deploy` service account exists with its four
      resource-scoped grants, **zero keys**, and exactly one member holding `serviceAccountTokenCreator` on it.
- [ ] **ecofolk#1112** merged (script hardening: rollback line, site name, temp `DOCKER_CONFIG` cleanup).
- [ ] `deploy-dev.sh` is on `main` (ecofolk#1111) and `HEAD` of your checkout is that exact tip.

### 1.2 Identity

Run it as `ecofolk-deploy`, **impersonated**, from Andy's own account in Cloud Shell. No key file is ever
created or read, and no credential stays on a fleet machine (ecofolk#1109). Set:

```bash
export ECOFOLK_DEPLOY_SA=<deploy-sa>   # the ecofolk-deploy address; not written here
export ECOFOLK_AR_REPO=<repo-id>       # the Artifact Registry repository id (infra#119)
export VITE_API_BASE_URL=<api-url> VITE_FIREBASE_API_KEY=<key> VITE_MAP_TILE_URL=<tile-url>
```

The `VITE_*` values are required: a production web build refuses without them. They are the owner's to
supply in the slot. Never paste them anywhere. The gate reads main's branch protection, which needs a
GitHub identity that can read it (repo admin). Without one the script refuses by design.

### 1.3 Steps

1. **Read what is serving now (slot start, read-only).** Before anything else:

   ```bash
   gcloud run services describe ecofolk-api --region <region> \
     --project=<project-id> --impersonate-service-account=<deploy-sa> \
     --format='value(status.traffic[0].revisionName,spec.template.spec.containers[0].image)'
   ```

   **Expected for slot 1:** the image is Google's `hello` placeholder
   (`us-docker.pkg.dev/cloudrun/container/hello`). No app image has ever been deployed: the module defaults
   to it and ignores image drift (`modules/cloudrun_api`). **If it shows anything else, stop and tell
   Architect**: something deployed outside this runbook. Note the revision name; it is the slot's rollback
   target (§2.2).

2. **Check first.** From a clean checkout at the main tip:

   ```bash
   scripts/deploy/deploy-dev.sh --check
   ```

   It checks every tool is on `PATH` (`git gh docker gcloud firebase npm curl`), runs every refusal, then
   stops before building anything. **Expected:** `gate passed: <sha> is PR #<n>, every required check
   succeeded`, then `--check: stopping before any build or deploy`. Any `REFUSED:` line is the answer; fix it
   and re-run. Do not continue past a refusal.

3. **Pre-flight the build host.** `--check` does not exercise `docker buildx`, and the real run builds with a
   throwaway, empty `DOCKER_CONFIG` that hides per-user plugins in `~/.docker/cli-plugins`. On a host whose
   only buildx lives there the build fails **after** the gate and **before** any push (it fails closed, but
   costs a slot). Check it now:

   ```bash
   DOCKER_CONFIG="$(mktemp -d)" docker buildx version
   ```

   **Expected:** a version line. Measured working on BigIron (system-wide buildx); **not measured in Cloud
   Shell** *(unobserved)*. If it errors, the buildx plugin must be installed system-wide before the slot.

4. **The real run:**

   ```bash
   scripts/deploy/deploy-dev.sh
   ```

   **Expected final line:** `deployed. revision=<revision> image=<digest> web_version=<name> sha=<sha>`.
   Copy those names (not env values) into §1.4, **and note the revision that was serving before** (§2.2
   step 1 reads it).

5. **Smoke test (ecofolk#410, PR ecofolk#1110).** The script's own smoke is read-only. The fuller smoke
   (sign-in, a sit, a photo upload, read-back, cleanup) is a separate command and has **no trigger yet**
   (deliberately, per the #883/#408 ruling): run it by hand, against the sha just deployed:

   ```bash
   npm run smoke --workspace packages/scripts -- --api <api-url> --web <web-url> --expect-sha <sha>
   ```

   It needs the smoke account (`SMOKE_EMAIL` + `SMOKE_PASSWORD` + `SMOKE_FIREBASE_API_KEY`, or
   `SMOKE_ID_TOKEN`) in the environment. **Exit 0** all checks passed. **1** a check failed: roll back (§2),
   because the new revision already holds 100% of traffic. **2** bad arguments or settings: nothing ran.
   A 409 on open-sit means the smoke account already has a sit open; the run refuses and touches nothing.
   Smoke-account provisioning is not written yet; until it is, this step cannot be run.

6. **Read-back, names only.** The revision holding 100% of traffic is the one the script printed, with the
   pushed digest:

   ```bash
   gcloud run services describe ecofolk-api --region <region> \
     --project=<project-id> --impersonate-service-account=<deploy-sa> \
     --format='value(status.latestReadyRevisionName,status.traffic[0].percent)'
   ```

   Print named fields only, never the whole service object (ecofolk#891).

### 1.4 Performed

**Performed: <date> by <who>, result**

### 1.5 Known gaps (ef-qa on #1111, Architect's stamp)

- **Unobserved until the first slot:** `firebase-tools` honouring the impersonated token
  (`GOOGLE_OAUTH_ACCESS_TOKEN`), `status.imageDigest` on revisions, and the startup-log "listening" line.
  If the script's smoke refuses on one of these, that is a finding about the script, not about the deploy:
  read the revision with the §1.3 step 6 command before deciding.
- **The registry login token sits on disk** in the throwaway `DOCKER_CONFIG` until the script's exit
  logout. It lasts about an hour; a killed run (SIGKILL) leaves it there until it expires, and the temp
  directory is not removed. Treat the Cloud Shell session as holding a short-lived credential until you've
  closed it (ecofolk#1112 covers the cleanup).
- **Site name:** the script's smoke URL derives from the project id, while `firebase.json` hard-codes
  `ecofolk-dev-web`. They agree for the default project only.
- **No schema step.** The script has no migration step: it deploys the API image and the web bundle and
  nothing else. A schema change is not part of this procedure and is not undone by §2.

## 2. Rollback

**State: DRAFT, never run.** Every command here is from gcloud and Firebase documentation, not run on this
stack *(unobserved)*. The deploy keeps every earlier Cloud Run revision, so the API rolls back by moving
traffic, not by rebuilding.

### 2.1 When

Any of: the smoke (§1.3 step 5) exits 1; the script's own smoke refuses; `/health` or `/ready` is not ok
after the deploy; or the owner says so. The deploy **already moved 100% of traffic** to the new revision, so
roll back first and diagnose afterwards.

### 2.2 API (Cloud Run)

1. **Name the revision to go back to.** Use the one that served before the deploy (read in §1.3 step 1).
   If you didn't note it, list them newest first:

   ```bash
   gcloud run revisions list --service=ecofolk-api --region <region> \
     --project=<project-id> --impersonate-service-account=<deploy-sa> --limit=5 \
     --format='table(metadata.name,metadata.creationTimestamp,status.conditions[0].status)'
   ```

   The newest is the bad one; take the one below it.

2. **Move all traffic to it:**

   ```bash
   gcloud run services update-traffic ecofolk-api --to-revisions=<previous-revision>=100 \
     --region=northamerica-northeast1 --project=<project-id> \
     --impersonate-service-account=<deploy-sa>
   ```

   `roles/run.developer` on the service covers this. **Expected:** the command prints the revision now at
   100%. Re-run the §1.3 step 6 read-back: it should name `<previous-revision>`.

3. **Verify:** `/health` is 200, and `/version` reports the **previous** sha (not the one you deployed).

### 2.3 Web (Firebase Hosting)

Roll the site back to its previous release:

```bash
firebase hosting:rollback --project <project-id>
```

Run it from `packages/web`, with the same impersonated token the script uses (`GOOGLE_OAUTH_ACCESS_TOKEN`).
It asks which site; the site is `ecofolk-dev-web` *(unobserved)*. Verify the web root serves and its version
is the previous one. If the web deploy never ran (the script stopped before it), skip this section.

### 2.4 Caveats

- **Slot 1: rolling back means "not deployed", which is safe.** Cloud Run has only ever served Google's
  `hello` placeholder, so the revision serving before the slot (read in §1.3 step 1) is the placeholder
  carrying the **current** env: each env change Terraform applies (infra#117, infra#66) creates a new
  placeholder revision, and the placeholder ignores env. Before beta opens, with no users, going back to it
  is an acceptable state (Architect, ecofolk-infra#121). Slot 1 does not need roll-forward-only.
- **Slot 2 onwards: the rollback target must postdate the last change to the API's env or secret
  contract.** A revision carries its own env and secret mapping. Any infra change that renames or removes an
  env var or secret (as ef#1108 did with `SWEEP_TOKEN`) makes every earlier app revision unsafe to roll back
  to: that is **roll-forward only**, and the infra PR making the change should announce it. Before using
  §2.2, check the target revision's creation time against the last such change.
- **No revision tags.** Do not add one (`--set-tags`): it edits the service's traffic configuration, which
  Terraform owns. Recording the revision name is enough (ecofolk#1112 makes the script record it).
- **Web, slot 1:** the Hosting rollback target is probably none, or the default page *(inferred, not
  measured)*. Read it at slot start with `firebase hosting:channel:list --site ecofolk-dev-web` and the
  site's releases list, and record what it shows here as measured. If there is no earlier release,
  `hosting:rollback` has nothing to go back to: leave the web as deployed and fix forward.
- **Traffic only.** Rolling back moves traffic; it does not undo a Terraform apply, a schema change or a
  secret rotation. Those have their own procedures (§3, §4).
- **Do not rebuild to roll back.** A rollback is `update-traffic` to a revision that already exists.

### 2.5 Performed

**Performed: <date> by <who>, result**

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
  versioned, so earlier nights are noncurrent versions of it. The one lifecycle rule deletes a noncurrent
  version 30 days after it was superseded, and only once it has at least 7 newer versions. No rule ever
  deletes a live object (ecofolk-infra#96).
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
     use the copy as `<export-uri>`. The copy is a live object, and no lifecycle rule ever deletes a live
     object (ecofolk-infra#96), so it stays (and bills) until you remove it in step 6. That removal is
     required.

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

6. **Clean up.** The script never deletes anything; you do. If this was a rehearsal, delete the target
   instance so it doesn't bill while idle:

   ```bash
   gcloud sql instances delete <target-instance>
   ```

   gcloud asks you to confirm.

   **Required if step 1 made a copy under `restore/`, rehearsal or not:** remove the copy. Nothing else
   removes it. Pass `--all-versions`: the bucket is versioned, so a plain `rm` only turns the copy into a
   noncurrent version, and the lifecycle rule never deletes that version because it never gets 7 newer
   versions.

   ```bash
   gcloud storage rm --all-versions gs://<project-id>-sql-exports/restore/ecofolk-<yyyymmdd>.sql.gz
   ```

   Then confirm nothing is left under `restore/`:

   ```bash
   gcloud storage ls --all-versions gs://<project-id>-sql-exports/restore/
   ```

   Expected: no objects listed (gcloud may report that the URL matched no objects).

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

---

## 5. Go-live checklist

Ordering rules learned the hard way. Each applies to every go-live paste, dev or prod.

- [ ] **A scheduler job must not go live before its destination's IAM.** A paste that SKIPs a gated step
  means the job it feeds stays disabled until that step runs. Before enabling a Cloud Scheduler job
  (or any timed export), confirm that every identity on the path can act: the one the job runs as can
  call the target API, and the one that writes to the destination can write (for a Cloud SQL export
  that is the instance's service account, not the scheduler's).
  Check the grant, not the Terraform plan: for the nightly export, the instance service account needs
  object-create and object-delete on the export bucket (`roles/storage.objectAdmin`; the job overwrites
  the previous night's fixed-name object, so create alone is not enough) before the 05:15 CT job is enabled.
  Verify with `gcloud storage buckets get-iam-policy gs://<project-id>-sql-exports` (add
  `--project=<project-id>`), not by waiting for the first run.
  *Source: ecofolk-infra#135. Four nightly exports failed 2026-10-17 to 2026-10-20 because the instance
  service account lacked object-create on the export bucket until the 2026-10-20 L-slot paste applied
  the gated grant.*

---

## 6. Firebase Auth role for the API runtime service account (ecofolk-infra#170)

IAM is hand-managed (ecofolk-infra#44), so this is a paste, not Terraform. Andy runs it (via the SME).

**Why.** The API verifies tokens with `checkRevoked`, which calls `getUser`, and suspend calls `updateUser`.
`roles/firebaseauth.viewer` can't write and is broader than needed. The custom role `ecofolkAuthUserManager`
holds exactly two permissions: `firebaseauth.users.get` and `firebaseauth.users.update`. It replaces the dev
viewer stopgap (ecofolk#1465).

**Scope.** One role and one grant per GCP project: the dev project (QA runs as dev's runtime SA in the same
project, so it needs nothing more) and `ecofolk-prod`. Set `PROJECT` to the dev project id and run the paste,
then run it again with `PROJECT=ecofolk-prod` (skip step 3 there).

```bash
PROJECT=<project-id>
SA=ecofolk-api@${PROJECT}.iam.gserviceaccount.com   # var.api_service_account_id's value

# 1. Create the role (skipped if it already exists).
gcloud iam roles describe ecofolkAuthUserManager --project="$PROJECT" >/dev/null 2>&1 || \
  gcloud iam roles create ecofolkAuthUserManager --project="$PROJECT" \
    --title="EcoFolk Auth user manager" \
    --permissions=firebaseauth.users.get,firebaseauth.users.update --stage=GA

# 2. Grant it to the runtime SA, in the project only.
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${SA}" \
  --role="projects/${PROJECT}/roles/ecofolkAuthUserManager" --condition=None --format=none

# 3. DEV ONLY, after step 2: remove the ecofolk#1465 stopgap.
gcloud projects remove-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${SA}" --role=roles/firebaseauth.viewer --format=none
```

`--format=none` matters: both binding commands otherwise print the project's WHOLE IAM policy, every member
included, into your terminal and any paste of it.

**Checks (read the grant, not the plan).**

```bash
gcloud iam roles describe ecofolkAuthUserManager --project="$PROJECT" --format='value(includedPermissions)'
# expect exactly: firebaseauth.users.get;firebaseauth.users.update
gcloud projects get-iam-policy "$PROJECT" --flatten='bindings[].members' \
  --filter="bindings.members:serviceAccount:${SA}" --format='value(bindings.role)'
# expect the custom role listed; in dev, roles/firebaseauth.viewer absent
```

**QA (ef-qa), dev:** suspending a user succeeds; that user's next request is refused; a normal signed-in request
through `checkRevoked` returns 200, not 503.

**Performed: <date> by <who>, result**

---

## 7. Session-triggered app deploy (ecofolk-infra#165)

`.github/workflows/deploy-app.yml` replaces the Cloud Shell deploy sittings. `scripts/deploy/deploy-dev.sh` in
ecofolk stays as the break-glass path.

**Run it** (from a session, on this repo's `main`):

```bash
gh workflow run deploy-app.yml -R rosebud785/ecofolk-infra -f env=dev -f sha=<40-hex ecofolk main commit>
```

Four jobs (#177): **resolve** (gate, checkout check, cloud auth, reads the API url and Firebase web key; id-token, no
npm), **build** (the app's `npm ci`, tsc and the web bundle; no id-token, no cloud credentials), **tools** (firebase-tools
from the lockfile in `tools/firebase/`, `npm ci --ignore-scripts`; no id-token, no ecofolk checkout, no app code) and
**deploy** (image, jobs, Cloud Run, Hosting, smoke; id-token, no npm). Only the public web bundle (`dist/`, plain files)
and the tools archive (pinned by a sha256 job output) pass between jobs as artifacts; the image is built in deploy because
an image artifact would publish private source from a public repo.

Dev runs on its own. **`env=prod` is not enabled yet**: step 1 refuses it and the `resolve` job's
`if: inputs.env == 'dev'` skips the run before any `environment:` reference, so a prod dispatch
cannot auto-create `gcp-prod`. The §A job split is done (#177); before enabling prod, note that each of the three jobs
names the environment, so prod would ask for the approve tap three times (resolve, build, deploy; `tools` names none). When prod is enabled it waits for Andy's Approve on the `gcp-prod` Environment. Rollback is a re-run with an
older main sha; the run prints the previous serving revision and the one-line traffic rollback.

**What it refuses** (as deploy-dev.sh does): a sha not reachable from ecofolk main; not exactly one merged PR; any
required check that is not SUCCESS on the merged head (SKIPPED refuses); a missing `VITE_*` value or a `demo-*`
project id; a failed check-config or migrate job (the API is then not deployed). It never passes env, secret or
service-account flags to Cloud Run. The old "listening in the startup log" smoke check is dropped (dev logs at warn);
`/health` (migrations checked, none pending), `/version == sha` and the web root replace it.

**Per environment (`gcp-dev`, later `gcp-prod`)**

| Kind | Name | Value |
|---|---|---|
| variable | `GCP_PROJECT_ID`, `GCP_REGION` | the project id, `northamerica-northeast1` |
| variable | `GCP_WIF_PROVIDER` | the Workload Identity provider resource name |
| variable | `GCP_DEPLOY_SA` | the `ecofolk-deploy` SA email |
| variable (optional) | `AR_REPO`, `API_SERVICE`, `MIGRATE_JOB`, `CHECK_CONFIG_JOB` | defaults `ecofolk`, `ecofolk-api`, `ecofolk-migrate`, `ecofolk-check-config` |
| secret | `ECOFOLK_READ_TOKEN` | fine-grained token on `rosebud785/ecofolk` only: Contents, Pull requests, Metadata, Administration (read only) |

**These are per-environment ONLY, never repository-level** variables or secrets: a repo-level value would be visible to
every environment (and to a future `gcp-prod` before its reviewer gate exists). Set them on the Environment itself.

`gcp-prod` also needs Andy as a required reviewer and deployment branches limited to `main`.

**Identity (a bootstrap paste, section B of the issue; the Deployer writes it, QA checks it before Andy runs it).**
Until it runs the workflow cannot authenticate. It must: add `attribute.workflow_ref` to the provider's mapping; trust
`ecofolk-deploy` only for `deploy-app.yml@refs/heads/main`; narrow `tf-apply`'s trust to `infra-apply.yml@refs/heads/main`
(required, so this workflow cannot ask for `tf-apply`'s token); and keep `ecofolk-deploy`'s roles narrow. It must also
grant `ecofolk-deploy` the custom role in section 8 (ecofolk-infra#173: `firebase.clients.get` and
`firebase.clients.list`), because the web key is read with `firebase apps:sdkconfig`. Then run the negative probes: a non-main ref, another
workflow on main, and this workflow asking for `tf-apply` must each be REFUSED.

---

## 8. Web config read for the deploy service account (ecofolk-infra#173)

IAM is hand-managed (ecofolk-infra#44), so this is a paste, not Terraform. It belongs in the #165 section B
bootstrap sitting; Andy runs it (via the SME).

**Why.** The deploy reads the web app's public client config (`firebase apps:sdkconfig web`) as the impersonated
`ecofolk-deploy` service account. That SA holds `firebasehosting.admin` and `logging.viewer`, and neither carries
`firebase.clients.get`, so the read is refused and a dev deploy needed the `ECOFOLK_DEPLOY_ENV_OVERRIDE=1` interim.

**Why a custom role, not a predefined one.** The predefined roles that carry `firebase.clients.get` (per Google's
role docs; not measured with `gcloud iam roles describe`, see the PR) bundle it with other Firebase permissions. The custom role `ecofolkDeployWebConfigReader` holds exactly two
permissions: `firebase.clients.get`, and `firebase.clients.list` because `apps:sdkconfig web` runs with no app id, so
the CLI lists the project's apps first (Architect, #182). It is a **separate role from `ecofolkAuthUserManager`** (section 6): that one is the API runtime SA's,
and the deploy SA must not gain user get/update.

**Scope.** One role and one grant per GCP project: dev now; `ecofolk-prod` when prod's deploy SA exists (the deploy
reads the key the same way there).

```bash
PROJECT=<project-id>
DEPLOY_SA=ecofolk-deploy@${PROJECT}.iam.gserviceaccount.com   # the GCP_DEPLOY_SA value

# 1. Create the role (skipped if it already exists).
gcloud iam roles describe ecofolkDeployWebConfigReader --project="$PROJECT" >/dev/null 2>&1 || \
  gcloud iam roles create ecofolkDeployWebConfigReader --project="$PROJECT" \
    --title="EcoFolk deploy web config reader" \
    --permissions=firebase.clients.get,firebase.clients.list --stage=GA

# 2. Grant it to the deploy SA, in the project only.
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${DEPLOY_SA}" \
  --role="projects/${PROJECT}/roles/ecofolkDeployWebConfigReader" --condition=None --format=none
```

**Checks (read the grant, not the plan).**

```bash
gcloud iam roles describe ecofolkDeployWebConfigReader --project="$PROJECT" --format='value(includedPermissions)'
# expect exactly: firebase.clients.get;firebase.clients.list
gcloud projects get-iam-policy "$PROJECT" --flatten='bindings[].members' \
  --filter="bindings.members:serviceAccount:${DEPLOY_SA}" --format='value(bindings.role)'
# expect the custom role listed alongside roles/firebasehosting.admin and roles/logging.viewer, nothing else new
```

**Verify the fix.** `deploy-dev.sh --check` (or the deploy-app workflow's "Resolve web build config" step) passes with
no `VITE_*` exported and no override. Before the grant the same check refuses with "firebase apps:sdkconfig failed".

---

## 9. Narrow the API runtime SA on the media bucket: objectAdmin to objectUser (ecofolk-infra#164)

IAM is hand-managed (ecofolk-infra#44), and `modules/media_bucket` declares no IAM resource by design, so this is a
paste, not Terraform. Andy runs it (via the SME) in the next booked slot, after the ecofolk#1417 freeze lifts.

**Why.** Dev's `ecofolk-api` SA holds `roles/storage.objectAdmin` on `gs://ecofolk-dev-media` (the old L-RUN
wording) alongside `roles/storage.objectUser`. The API only creates, reads, lists and deletes objects
(`packages/api/src/media/gcs-storage.ts`: `save`, `download`, `exists`, `getFiles`, `delete`); it never sets an IAM
policy or ACL. `objectUser` covers all of that and has no object or managed-folder IAM admin. Prod is P15 of the
go-live checklist and gets `objectUser` from day one, so this paste is dev only.

```bash
PROJECT=<dev-project-id>
SA=ecofolk-api@${PROJECT}.iam.gserviceaccount.com
BUCKET=gs://${PROJECT}-media

# 1. Make sure objectUser is held BEFORE objectAdmin goes (it already is in dev; this is idempotent).
gcloud storage buckets add-iam-policy-binding "$BUCKET" \
  --member="serviceAccount:${SA}" --role=roles/storage.objectUser --format=none

# 2. Remove the broader grant.
gcloud storage buckets remove-iam-policy-binding "$BUCKET" \
  --member="serviceAccount:${SA}" --role=roles/storage.objectAdmin --format=none
```

**Check (read the grant, not the plan).**

```bash
gcloud storage buckets get-iam-policy "$BUCKET" --flatten='bindings[].members' \
  --filter="bindings.members:serviceAccount:${SA}" --format='value(bindings.role)'
# expect EXACTLY one line: roles/storage.objectUser   (objectAdmin absent)
```

**After it.** A dev upload, a media read and a delete (or the TTL sweep) still succeed as that SA. If any is
refused, re-add `roles/storage.objectAdmin` with the step 1 command and report the denied call on #164.
Out of scope: the export bucket's objectAdmin (P13), which #135 measured as needed.

---

## 10. PR-time plan: the read-only `tf-plan` identity (ecofolk-infra#162)

`infra-plan.yml` lets a reviewer read the REAL dev `terraform plan` of an open PR before it merges (Architect ruling
c7084664707, option B). IAM is hand-managed (ecofolk-infra#44), so the identity is a paste, not Terraform. Andy runs it
(via the SME). **Order: the PR merges first, then this paste, then the first dispatch.** Nothing here runs before merge.

**Run it** (from a session, on this repo's `main`; there is deliberately no `pull_request` trigger):

```bash
gh workflow run infra-plan.yml -R rosebud785/ecofolk-infra -f pr=<open PR number>
```

It posts a **names-only** comment on the PR: each changed resource's address, its actions and the NAMES of the
attributes that change, with destroy and replace called out at the top, and a machine line
`plan-record: <pr-head-sha> <hash>`. No value is posted, sensitive or not (this repo is public).

**What it refuses before it plans** (`scripts/check-plan-tree.sh`, run from `main`'s copy, before `terraform init` and
before auth). It judges the **parse tree**, not the text: every `.tf` and lockfile goes through `hcl2json` (HashiCorp
hcl/v2, the parser Terraform uses), pinned by sha256 in `scripts/fetch-hcl2json.sh` and fetched in CI only, so an
unquoted label (`provider google {`) or a leading `/* … */` cannot hide a construct, and a file that does not parse is a
refusal. Locally the rules are judged on committed JSON (`scripts/tests/hcl/cache/`), and CI proves that JSON is exactly
what the pinned binary emits. The refusals: the PR is not open, is from a fork, or does not target `main`; the tree has a `data "external"` /
`data "http"`, a provider `external` / `http` / `local` / `null`, any resource or data type that does not start with `google_` or `archive_` (an allowlist: the built-in `terraform_remote_state` is refused, wherever the block is nested), any top-level block kind other than `terraform`, `provider`, `variable`, `locals`, `output`, `module`, `resource`, `data`, `moved`, `import` and `removed` (so `check`, `ephemeral` and any future kind are refused by name), a `provisioner`, a module
`source` that is not a local path, a `*.tf.json`, or a provider outside `PLAN_PROVIDER_ALLOWLIST` (in the workflow, on
`main`: today `hashicorp/google`, `hashicorp/google-beta`, `hashicorp/archive`, exactly what the lockfiles hold). Also
refused, because they run at plan time or pick where the credential goes: an `output_path` that is not exactly
`"${path.root}/.terraform/tmp/<file name>"` (the archive data source WRITES a file at plan time); a backend that is not
exactly one `backend "gcs"` with only `prefix = "<literal>"` in `environments/dev`, any `cloud` block, any backend of
another type, any backend in a module; a `*_custom_endpoint` attribute; any symbolic link or committed `.terraform`
directory; a local module whose path leaves the tree; any `.tf` or lockfile that does not parse; and, in a `provider "google"`
or `"google-beta"` block, any attribute or nested block other than `project`, `region`, `zone`, `alias` and
`default_labels` (an allowlist, so a credential, token, impersonation, universe or endpoint change, or anything a
future provider version adds, is refused without anyone naming it). CI runs the same script on this repo's own tree, so
a rule that would refuse today's code fails at review. Such a
PR gets a comment saying there is no PR-time plan and records `plan-record: <sha> static-refused`; the apply's own plan
is then the first one, as before.

**The boundary, and the accepted residual** (Architect design review, infra#162 c7091748530). Static refusal is defence in
depth, not the boundary: the boundary is `tf-plan`'s blast radius, which is why the paste below grants exactly the three
roles and nothing else, why the dev state must hold no secret values (the Deployer confirms, names only), and why the
token lives for the job only. Data reaching Google's APIs (including another project's logs) at `tf-plan`'s privilege is
the accepted residual: no HCL rule can tell our project from one the PR author controls, and the egress is
`googleapis.com` itself. A newly found form that only reaches that residual is a note, not a block.

**The drift rule.** `infra-apply.yml` still re-plans on merge and applies its own saved plan, but a plan WITH changes
applies only if `scripts/check-plan-record.sh` finds, for the merged PR: the merge commit's tree equals the PR head's
tree (use strict "up to date" branch protection, or merge only a PR that is current with `main`), and the latest
`plan-record` for that head has the hash of the apply's own plan (or says `static-refused`). The hash covers each
changed resource's address, its actions and the full list of changed attribute NAMES (never a value), so an apply that
updates different attributes than the reviewer saw does not match. A record counts only as the LAST line of a comment by
`github-actions[bot]` whose FIRST line is one of the two headers `infra-plan.yml` writes.
No record, a different tree or a different hash: the apply REFUSES, applies nothing, and the run goes red. Recovery is a
fresh `infra-plan.yml` dispatch on the PR's head, then a re-run of the apply. While `TF_APPLY_ENABLED` is not `true` the
existing gate already refuses any change; that behaviour is kept.

**Variables.** One new repo variable: `GCP_PLAN_SA` (the `tf-plan` SA email). It reuses `GCP_PROJECT_ID`,
`GCP_WIF_PROVIDER`, `TF_STATE_BUCKET`, `ALERT_CHANNEL_IDS` and the two log-filter variables. Repository-level, because
the plan job names no Environment (a read-only identity bound to a workflow file on `main`).

**The paste (copy it; nothing in it is a value).** Section 7's step "add `attribute.workflow_ref` to the provider's
mapping" must already have run; step 4 below checks it.

```bash
PROJECT=<dev-project-id>
STATE_BUCKET=<tf-state-bucket>          # the repo variable TF_STATE_BUCKET
POOL=<workload-identity-pool-id>        # the pool that GCP_WIF_PROVIDER belongs to
PROVIDER=<workload-identity-provider-id>
REPO=rosebud785/ecofolk-infra
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
PLAN_SA="tf-plan@${PROJECT}.iam.gserviceaccount.com"

# 1. The identity: read-only, no key.
gcloud iam service-accounts describe "$PLAN_SA" --project="$PROJECT" >/dev/null 2>&1 || \
  gcloud iam service-accounts create tf-plan --project="$PROJECT" \
    --display-name="Terraform PR-time plan (read-only)"

# 2. Its roles: read the project, read the state (objectViewer on the state bucket ONLY), read Secret Manager METADATA.
#    NEVER roles/secretmanager.secretAccessor.
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${PLAN_SA}" --role=roles/viewer --condition=None --format=none
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${PLAN_SA}" --role=roles/secretmanager.viewer --condition=None --format=none
gcloud storage buckets add-iam-policy-binding "gs://${STATE_BUCKET}" \
  --member="serviceAccount:${PLAN_SA}" --role=roles/storage.objectViewer --format=none

# 3. Trust: ONLY infra-plan.yml at refs/heads/main may impersonate it. The workflow_ref value carries the repository
#    name, so the repository is pinned by the same condition.
gcloud iam service-accounts add-iam-policy-binding "$PLAN_SA" --project="$PROJECT" \
  --role=roles/iam.workloadIdentityUser --format=none \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.workflow_ref/${REPO}/.github/workflows/infra-plan.yml@refs/heads/main"

# 4. The provider must map workflow_ref (section 7), or step 3 trusts nothing.
gcloud iam workload-identity-pools providers describe "$PROVIDER" --workload-identity-pool="$POOL" \
  --location=global --project="$PROJECT" --format='value(attributeMapping)' | tr ',' '\n' | grep -c 'workflow_ref'
# expect 1 or more

# 5. The repo variable.
gh variable set GCP_PLAN_SA --repo "$REPO" --body "$PLAN_SA"
```

**Check (read the grants, not the plan).**

```bash
# roles on the project: expect exactly roles/viewer and roles/secretmanager.viewer
gcloud projects get-iam-policy "$PROJECT" --flatten='bindings[].members' \
  --filter="bindings.members:serviceAccount:${PLAN_SA}" --format='value(bindings.role)'
# on the state bucket: expect exactly roles/storage.objectViewer
gcloud storage buckets get-iam-policy "gs://${STATE_BUCKET}" --flatten='bindings[].members' \
  --filter="bindings.members:serviceAccount:${PLAN_SA}" --format='value(bindings.role)'
# who may impersonate it: expect exactly the one principalSet from step 3
gcloud iam service-accounts get-iam-policy "$PLAN_SA" --project="$PROJECT" --format='value(bindings.members)'
# no user-managed keys: expect no output
gcloud iam service-accounts keys list --iam-account="$PLAN_SA" --managed-by=user --project="$PROJECT" --format='value(name)'
```

**Negative probes (each must be REFUSED):** `deploy-app.yml` on `main` asking for `tf-plan`; `infra-plan.yml` on any
ref other than `main` asking for `tf-plan`; `infra-plan.yml` on `main` asking for `tf-apply` (section 7 narrowed
`tf-apply`'s trust to `infra-apply.yml@refs/heads/main`).

**After it.** The first dispatch on a real PR proves the role set. If a read is refused (403), the plan job's log names
the permission: add the narrowest read role that covers it, name it on #162, and re-run. Do not grant anything that
can write, and do not grant `secretAccessor`. Prod is the same mechanism with its own plan SA once `environments/prod`
exists, under ecofolk#400's gates.
