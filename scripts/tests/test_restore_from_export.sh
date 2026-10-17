#!/usr/bin/env bash
# test_restore_from_export.sh — proves restore-from-export.sh (ecofolk-infra#3) can go red, not just
# green. Runs the script against a STUBBED gcloud on PATH (never the real one, never GCP): the stub logs
# every call and answers execute-sql from FAKE_* variables, so each case controls what the "restored"
# database holds. AC on #3: the happy path, a missing `vector` (must fail), and a missing table.
#
# Usage: bash scripts/tests/test_restore_from_export.sh
# Exit: 0 if every case matches its expected outcome, 1 otherwise.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESTORE="$SCRIPT_DIR/../restore-from-export.sh"

pass=0; fail=0
check() {
  local name="$1" cond="$2"
  if eval "$cond"; then echo "PASS  $name"; pass=$((pass+1));
  else echo "FAIL  $name  (condition: $cond)"; fail=$((fail+1)); fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The stub. FAKE_EXTENSIONS: space-separated extensions present. FAKE_TABLES: space-separated
# <table>:<rows>. FAKE_FAIL: a gcloud subcommand (create | import | execute-sql) that exits 1.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gcloud" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GCLOUD_LOG"
row() { printf '{"results":[{"columns":[{"name":"count"}],"rows":[{"values":[{"value":"%s"}]}]}]}\n' "$1"; }
case "$1 $2 $3" in
  "sql databases create") [ "${FAKE_FAIL:-}" = create ] && { echo "ERROR: create failed" >&2; exit 1; }; exit 0 ;;
  "sql import sql")       [ "${FAKE_FAIL:-}" = import ] && { echo "ERROR: import failed" >&2; exit 1; }; exit 0 ;;
  "sql instances execute-sql")
    [ "${FAKE_FAIL:-}" = execute-sql ] && { echo "ERROR: execute-sql failed" >&2; exit 1; }
    sql=""
    for a in "$@"; do case "$a" in --sql=*) sql="${a#--sql=}" ;; esac; done
    if [[ "$sql" =~ extname\ =\ \'([a-z_]+)\' ]]; then
      e="${BASH_REMATCH[1]}"
      case " ${FAKE_EXTENSIONS:-} " in *" $e "*) row 1 ;; *) row 0 ;; esac
      exit 0
    fi
    if [[ "$sql" =~ to_regclass\(\'([a-z0-9_.]+)\'\) ]]; then
      t="${BASH_REMATCH[1]}"
      for kv in ${FAKE_TABLES:-}; do [ "${kv%%:*}" = "$t" ] && { row 1; exit 0; }; done
      row 0; exit 0
    fi
    if [[ "$sql" =~ FROM\ ([a-z0-9_.]+)\; ]]; then
      t="${BASH_REMATCH[1]}"
      for kv in ${FAKE_TABLES:-}; do [ "${kv%%:*}" = "$t" ] && { row "${kv#*:}"; exit 0; }; done
      echo "ERROR: relation \"$t\" does not exist" >&2; exit 1
    fi
    echo "stub: unexpected sql: $sql" >&2; exit 1 ;;
  *) echo "stub: unexpected gcloud call: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$WORK/bin/gcloud"

URI="gs://example-dev-sql-exports/ecofolk.sql.gz"
TARGET="ecofolk-pg-restore"
ALL_TABLES="users:12 public.sites:3 observations:40"

# run <case-name> [VAR=value ...] -- <args...>: runs the script with the stub, sets OUT, RC, LOG.
run() {
  local name="$1"; shift
  local envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  export GCLOUD_LOG="$WORK/$name.log"
  : > "$GCLOUD_LOG"
  OUT=$(env PATH="$WORK/bin:$PATH" FAKE_EXTENSIONS="" FAKE_TABLES="" FAKE_FAIL="" "${envs[@]}" \
    bash "$RESTORE" "$@" 2>&1); RC=$?
  LOG=$(cat "$GCLOUD_LOG")
}

# 1. Happy path: both extensions, all 3 tables. Exits 0, in the order create -> import -> checks.
run happy FAKE_EXTENSIONS="postgis vector" FAKE_TABLES="$ALL_TABLES" -- "$URI" "$TARGET" users public.sites observations
check "happy: exits 0" "[ $RC -eq 0 ]"
check "happy: reports RESTORE_OK" "echo \"\$OUT\" | grep -q RESTORE_OK"
check "happy: creates database ecofolk on the target" "echo \"\$LOG\" | sed -n 1p | grep -q '^sql databases create ecofolk --instance=$TARGET'"
check "happy: imports the export into ecofolk second" "echo \"\$LOG\" | sed -n 2p | grep -q '^sql import sql $TARGET $URI --database=ecofolk'"
check "happy: every query goes to the target's ecofolk database" "echo \"\$LOG\" | grep -q 'execute-sql' && ! echo \"\$LOG\" | grep 'execute-sql' | grep -vq -- 'execute-sql $TARGET --database=ecofolk '"
check "happy: checks postgis" "echo \"\$OUT\" | grep -q 'ok  extension postgis'"
check "happy: checks vector" "echo \"\$OUT\" | grep -q 'ok  extension vector'"
check "happy: prints each table's row count" "echo \"\$OUT\" | grep -q 'ok  table users rows=12' && echo \"\$OUT\" | grep -q 'ok  table public.sites rows=3' && echo \"\$OUT\" | grep -q 'ok  table observations rows=40'"

# 2. Missing vector (postgis only, the ef#455 case): MUST fail, naming vector.
run no-vector FAKE_EXTENSIONS="postgis" FAKE_TABLES="$ALL_TABLES" -- "$URI" "$TARGET" users public.sites observations
check "missing vector: exits 1" "[ $RC -eq 1 ]"
check "missing vector: names vector" "echo \"\$OUT\" | grep -q 'RESTORE_FAILED: extension vector is missing'"
check "missing vector: no RESTORE_OK" "! echo \"\$OUT\" | grep -q RESTORE_OK"

# 3. Missing postgis (vector only): the mirror case fails too.
run no-postgis FAKE_EXTENSIONS="vector" FAKE_TABLES="$ALL_TABLES" -- "$URI" "$TARGET" users public.sites observations
check "missing postgis: exits 1" "[ $RC -eq 1 ]"
check "missing postgis: names postgis" "echo \"\$OUT\" | grep -q 'RESTORE_FAILED: extension postgis is missing'"

# 4. Missing table: the third table isn't in the restored database. Fails, naming it.
run no-table FAKE_EXTENSIONS="postgis vector" FAKE_TABLES="users:12 public.sites:3" -- "$URI" "$TARGET" users public.sites observations
check "missing table: exits 1" "[ $RC -eq 1 ]"
check "missing table: names the table" "echo \"\$OUT\" | grep -q 'RESTORE_FAILED: table observations is missing'"
check "missing table: no RESTORE_OK" "! echo \"\$OUT\" | grep -q RESTORE_OK"

# 5. A failed import stops the run before any check, and fails.
run import-fails FAKE_FAIL=import FAKE_EXTENSIONS="postgis vector" FAKE_TABLES="$ALL_TABLES" -- "$URI" "$TARGET" users public.sites observations
check "import fails: exits 1" "[ $RC -eq 1 ]"
check "import fails: names the import" "echo \"\$OUT\" | grep -q 'RESTORE_FAILED: import'"
check "import fails: runs no query" "! echo \"\$LOG\" | grep -q execute-sql"

# 6. A failed database create stops the run before the import.
run create-fails FAKE_FAIL=create -- "$URI" "$TARGET" users public.sites observations
check "create fails: exits 1" "[ $RC -eq 1 ]"
check "create fails: never imports" "! echo \"\$LOG\" | grep -q 'sql import'"

# 7. An execute-sql error is a failure, never a pass.
run query-fails FAKE_FAIL=execute-sql FAKE_EXTENSIONS="postgis vector" FAKE_TABLES="$ALL_TABLES" -- "$URI" "$TARGET" users public.sites observations
check "query error: exits 1" "[ $RC -eq 1 ]"
check "query error: no RESTORE_OK" "! echo \"\$OUT\" | grep -q RESTORE_OK"

# 8. Bad arguments exit 2 and call gcloud not at all.
run two-tables -- "$URI" "$TARGET" users public.sites
check "2 tables: exits 2" "[ $RC -eq 2 ] && [ -z \"\$LOG\" ]"
run bad-uri -- "/tmp/ecofolk.sql.gz" "$TARGET" users public.sites observations
check "non-gs:// uri: exits 2" "[ $RC -eq 2 ] && [ -z \"\$LOG\" ]"
run sql-in-table -- "$URI" "$TARGET" users "x; DROP TABLE users" observations
check "SQL in a table name: exits 2, no gcloud call" "[ $RC -eq 2 ] && [ -z \"\$LOG\" ]"
run live-target -- "$URI" ecofolk-pg users public.sites observations
check "live instance ecofolk-pg as target: exits 2, no gcloud call" "[ $RC -eq 2 ] && [ -z \"\$LOG\" ]"

echo ""
echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
