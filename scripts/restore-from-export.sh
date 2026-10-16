#!/usr/bin/env bash
# restore-from-export.sh — restore the nightly SQL export (ecofolk-infra#2, C2) into a fresh Cloud SQL
# instance, then prove the restore is usable (ecofolk-infra#3, C3). This is the script the runbook's
# Restore procedure (docs/runbook.md §3) performs; ef#405 runs it on-site. Nothing in CI runs it.
#
# What it does, in order, stopping at the first failure:
#   1. creates the database `ecofolk` on <target-instance>;
#   2. imports <export-uri> into it (gcloud sql import sql);
#   3. asserts that `postgis` AND `vector` both exist in the restored database, each checked on its own
#      (ef#455: a check that passed with only one of the two is the bug this exists to prevent);
#   4. asserts that each of the 3 named tables exists, and prints its row count.
#
# USAGE
#   bash scripts/restore-from-export.sh <export-uri> <target-instance> <table1> <table2> <table3>
#   e.g. bash scripts/restore-from-export.sh gs://<project-id>-sql-exports/ecofolk.sql.gz \
#          <target-instance> <schema.table> <table> <table>
#   The project is gcloud's own (gcloud config, or CLOUDSDK_CORE_PROJECT).
#
# EXIT: 0 = database created, export imported, both extensions present, all 3 tables present.
#       1 = any step failed or any check missed (the line names which).
#       2 = bad arguments; nothing was run.
#
# What it does NOT do (spec on #3, narrower reading):
#   - create or delete <target-instance>. The operator creates the fresh instance first (Postgres 16,
#     northamerica-northeast1) and removes it after a rehearsal (runbook §3.2 step 6);
#   - compare row counts against expected values. It prints `<table> rows=<n>`; the operator records
#     them against the counts known as of the export (runbook §3.3).
#
# Output is named fields only (extension names, table names, counts): it never prints a whole gcloud
# response, an instance description, or anything from an auth or IAM object.
#
# Queries go through `gcloud sql instances execute-sql` against <target-instance>, so no psql and no
# network path to the private IP are needed. Tests: scripts/tests/test_restore_from_export.sh (stubbed
# gcloud; never reaches GCP).
#
# LOCAL FOLLOW-UP (IAM is never written in this public repo; a human-side session grants these):
#   1. The target instance's own service account needs roles/storage.objectViewer on the export bucket
#      (<project-id>-sql-exports): the import reads the object as that account.
#   2. The operator running this needs an IAM database user on <target-instance> (execute-sql connects
#      as the caller's Google account), plus roles/cloudsql.admin (or narrower: databases.create,
#      instances.import, instances.executeSql) on the project.
set -uo pipefail

DATABASE="ecofolk"                # modules/cloudsql: the one database, and what the nightly export holds
LIVE_INSTANCE="ecofolk-pg"        # modules/cloudsql default; never restore over it
EXTENSIONS=(postgis vector)       # both, each on its own (ef#455)

usage() {
  echo "usage: $0 <export-uri> <target-instance> <table1> <table2> <table3>" >&2
  exit 2
}

[ "$#" -eq 5 ] || usage
EXPORT_URI="$1"
TARGET="$2"
shift 2
TABLES=("$@")

[[ "$EXPORT_URI" =~ ^gs://[a-z0-9][a-z0-9._-]*/.+ ]] || { echo "ARG ERROR: export-uri must be gs://<bucket>/<object>, got: $EXPORT_URI" >&2; exit 2; }
[[ "$TARGET" =~ ^[a-z][a-z0-9-]{0,96}$ ]] || { echo "ARG ERROR: target-instance is not a valid Cloud SQL instance name: $TARGET" >&2; exit 2; }
[ "$TARGET" != "$LIVE_INSTANCE" ] || { echo "ARG ERROR: refusing to restore into the live instance $LIVE_INSTANCE; use a fresh instance" >&2; exit 2; }
# Table names are interpolated into SQL, so only plain (optionally schema-qualified) identifiers pass.
for t in "${TABLES[@]}"; do
  [[ "$t" =~ ^[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)?$ ]] || { echo "ARG ERROR: table must be a plain identifier ([schema.]name, lower case): $t" >&2; exit 2; }
done

command -v gcloud >/dev/null 2>&1 || { echo "FAIL: gcloud not found on PATH" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 not found on PATH (parses execute-sql results)" >&2; exit 1; }

fail() { echo "RESTORE_FAILED: $*"; exit 1; }

# sql_scalar <sql>: run one statement in the restored database and print the first column of the first
# row. Fails (non-zero, nothing printed) if gcloud fails or the response holds no such value, so an error
# response can never read as a value.
sql_scalar() {
  local out
  out=$(gcloud sql instances execute-sql "$TARGET" --database="$DATABASE" --sql="$1" --format=json) || return 1
  printf '%s' "$out" | python3 -I -c '
import json, sys
try:
    v = json.load(sys.stdin)["results"][0]["rows"][0]["values"][0]
except (ValueError, KeyError, IndexError, TypeError):
    sys.exit(1)
if not isinstance(v, dict) or v.get("nullValue") or "value" not in v:
    sys.exit(1)
print(v["value"])
'
}

echo "== restore $EXPORT_URI -> $TARGET (database $DATABASE)"

echo "-- 1/4 create database"
gcloud sql databases create "$DATABASE" --instance="$TARGET" --quiet || fail "could not create database $DATABASE on $TARGET"

echo "-- 2/4 import"
gcloud sql import sql "$TARGET" "$EXPORT_URI" --database="$DATABASE" --quiet || fail "import of $EXPORT_URI into $TARGET failed"

echo "-- 3/4 extensions"
for ext in "${EXTENSIONS[@]}"; do
  n=$(sql_scalar "SELECT count(*) FROM pg_extension WHERE extname = '$ext';") || fail "could not query pg_extension for $ext"
  [ "$n" = "1" ] || fail "extension $ext is missing from $DATABASE on $TARGET"
  echo "ok  extension $ext"
done

echo "-- 4/4 tables"
for t in "${TABLES[@]}"; do
  present=$(sql_scalar "SELECT count(*) FROM pg_class WHERE oid = to_regclass('$t');") || fail "could not look up table $t"
  [ "$present" = "1" ] || fail "table $t is missing from $DATABASE on $TARGET"
  rows=$(sql_scalar "SELECT count(*) FROM $t;") || fail "could not count rows in $t"
  [[ "$rows" =~ ^[0-9]+$ ]] || fail "row count for $t is not a number"
  echo "ok  table $t rows=$rows"
done

echo "RESTORE_OK: $TARGET database $DATABASE has postgis and vector, and all 3 tables."
