# Alerting policy

Rules the alerts in `modules/monitoring` depend on. The alerts themselves are in `alerts.tf`.

## Scheduler invariant: nothing touches the dev database while it is stopped

Dev Cloud SQL is stopped nightly, 22:15–04:45 CT (`modules/sql_off_hours`, ecofolk-infra#14). The
DB connection failure alert (`alerts.tf`, alert 2) is a log-based metric, and a log filter cannot be
scoped to a time of day, so the alert cannot ignore that window. Anything that connects during it pages.

**The invariant:** every Cloud Scheduler job that touches the database

1. sets `time_zone = "America/Chicago"`, and
2. has no run inside the 22:15–04:45 CT stop window.

Current jobs (`sync-usgs-water` is defined in the ecofolk repo, so its row is recorded here, not enforced here):

| Job | Module | Schedule (CT) | Inside the window? |
|---|---|---|---|
| `sql_export` | `modules/cloudsql` | `15 5 * * *` | No (05:15) |
| `idle-sit-sweep` | `modules/idle_sit_sweep` | `0 5-21/2 * * *` in `environments/dev` | No (05:00–21:00) |
| `sync-usgs-water` | ecofolk (ef PR #1105; not in this repo) | `0 5,11,17 * * *` | No (05:00, 11:00, 17:00) |

The `idle_sit_sweep` module default (`0 */2 * * *`) does run inside the window (00:00, 02:00, 04:00).
It is safe only because `environments/dev` overrides it, so any new environment that has a stopped
database must do the same.

`sql_off_hours`' own stop and start jobs are the cause of the window, not subject to it.

Both `sql_export` and `idle_sit_sweep` already assert `time_zone == "America/Chicago"` in their
`tftest.hcl` files. A new DB-touching job needs the same assertion and a schedule outside the window.

Origin: ef#894 (Architect ruling).
