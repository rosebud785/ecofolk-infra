# Reference data on Cloud SQL: volume and cost

ecofolk-infra#29 (EcoFolk plan row E-19). Reference data is what the ingest jobs pull from outside
sources (USGS water, NOAA weather, USDA soils, iNaturalist) into the app's Postgres database. This page
says how much of it there is, how fast it grows, and what it costs on the Cloud SQL instance that
[`cost-model.md`](cost-model.md) prices.

Every number on this page belongs to exactly one of three classes, and no figure mixes them:

| Class | What it means | Where it comes from |
| --- | --- | --- |
| **MEASURED** | Read from the dev database. | The L-REFSIZE comment on #29 (issue comment 6275687361), quoted as posted. |
| **DERIVED** | Arithmetic on measured inputs only. Every input and step is shown. *Derived, not observed.* | This page. |
| **NOT YET MEASURABLE** | No number is given. | The reason, and the run that would measure it. |

No public or external estimate fills any gap on this page. Prices are the ones already in
[`cost-model.csv`](cost-model.csv) (read 2026-10-14).

## The conclusion

**Measured + derived floor; iNat unknown.**

- **Measured:** the 11 reference-data tables hold 1,160 kB, in a 22 MB database.
- **Derived floor:** the one table that grows, `water_readings`, would add about 0.11 GiB in a year
  of continuous sync for the 2 gauges it holds now.
- **Unknown:** iNaturalist has never run, so its volume has no number, and neither does growth per
  place.

On what this repo provisions, the measured and derived volumes **add nothing to the bill**. They sit
inside the 10 GiB SSD disk that the `sql-storage` line already pays for in full ($1.87 a month), and
fill about 0.2% of it now (the whole database) and about 1.3% after the derived year (see
[Cost](#cost)). That conclusion holds with every gap left empty. It stops holding only if a gap, most likely iNat, turns out to need
several GiB, and that can't be known until the gap is measured.

## 1. MEASURED

**Source:** L-REFSIZE (ecofolk#1106), posted on #29, measured **2026-10-19 at about 19:38 UTC**.
Read-only, on the dev database of the main dev stack (stack A). The second dev stack (stack B) was not
measured. Sizes are `pg_total_relation_size`, so they include indexes and TOAST. Row counts are exact
`count(*)`.

- **Whole database:** 22 MB.
- **The 11 reference-data tables:** 1,160 kB in total.
- **Places seeded:** 2.

| Table | Source | Rows | Size (bytes) |
| --- | --- | ---: | ---: |
| `soil_map_units` | USDA soils | 16 | 352,256 |
| `water_readings` | USGS water | 754 | 319,488 |
| `weather_normals` | NOAA weather | 60 | 81,920 |
| `sync_runs` | sync bookkeeping | 3 | 81,920 |
| `sync_checkpoints` | sync bookkeeping | 3 | 81,920 |
| `water_gauges` | USGS water | 2 | 73,728 |
| `inat_observations` | iNaturalist | 0 | 73,728 |
| `inat_taxa` | iNaturalist | 0 | 49,152 |
| `weather_stations` | NOAA weather | 1 | 32,768 |
| `place_water_gauges` | place link | 0 | 24,576 |
| `place_context_cache` | place cache | 0 | 16,384 |
| **Total** | | | **1,187,840 (1,160 kB)** |

The Source column groups the tables by name and by the sync run that wrote them, as the measurement
describes them. The total is the sum of the rows above.

**Ingest history, as measured.** `sync_runs` holds 3 rows, one per source, and all 3 succeeded:

| Source | Run (UTC) |
| --- | --- |
| `usgs_water` | 2026-09-29 00:38 |
| `noaa_weather` | 2026-09-29 21:48 |
| `usda_soils` | 2026-09-30 21:51 |

Nothing has run since 2026-09-30. The iNaturalist sync has never run on this database.

- `weather_normals` (60 rows: 1 station × 12 months × 5 values), `soil_map_units` (16) and
  `weather_stations` (1) were each written by their one run. They are snapshots, and their measured
  weekly delta is 0.
- All 754 `water_readings` rows came from the one 2026-09-29 run, covering 24 hours of readings
  (`observed_at` 2026-09-28 00:40 → 2026-09-29 00:30 UTC) for 2 gauges × 2 parameters:

  | Gauge | Rows per parameter in 24 h | Cadence | Rows in 24 h (× 2 parameters) |
  | --- | ---: | --- | ---: |
  | gauge 1 | 285 | 5 minutes | 570 |
  | gauge 2 | 92 | 15 minutes | 184 |
  | **Both** | | | **754** |

**Which table dominates now.** `soil_map_units` (352,256 bytes) and `water_readings` (319,488 bytes)
are 57% of the reference total between them. At this size most tables are dominated by Postgres's
fixed page and index overhead, not by their rows: the two empty iNat tables take 122,880 bytes. So
the ranking says little about the future. Only `water_readings` grows on its own (see below).

## 2. DERIVED (derived, not observed)

Only `water_readings` accumulates, so it is the only table with a growth figure. Nothing below has been
observed: no second USGS run exists.

### Inputs

| # | Input | Value | Class |
| --- | --- | --- | --- |
| I1 | Rows written by the one USGS run, covering 24 h | 754 | measured |
| I2 | Rows per parameter per 24 h: gauge 1, gauge 2 | 285, 92 | measured |
| I3 | Parameters per gauge | 2 | measured |
| I4 | `water_readings` size for 754 rows | 319,488 bytes | measured |
| I5 | Nominal cadence: gauge 1, gauge 2 (readings per 24 h) | 5 min (288), 15 min (96) | read from I2 by L-REFSIZE |
| A1 | The sync runs often enough, and its checkpoint resumes where it stopped, so every reading is stored once | assumption | not measured |

**Job cadence.** The USGS sync's schedule is in the app's code, not in this repo: no
`google_cloud_scheduler_job` here runs a reference sync (`environments/dev`'s `scheduler_jobs` output
holds 4 jobs, none of them ingest). How often the job runs doesn't change the row count under A1,
because each reading is stored once whenever it is fetched. The growth below is set by the gauges'
reading cadence, which *is* measured (I2). If a run is missed for longer than the source keeps data, A1
fails and the real figure is lower.

### Rows

- **Per week, from the measured day:** 754 × 7 = **5,278 rows**.
- **Per week, at the nominal cadence:** (288 + 96) × 2 parameters × 7 days = **5,376 rows**. This is
  the "about 5,400 rows a week" in L-REFSIZE's comment.
- **Per year, from the measured day:** 754 × 365 = **275,210 rows**.
- **Per year, at the nominal cadence:** (288 + 96) × 2 × 365 = **280,320 rows**.
- **Per gauge per year, from the measured day:** gauge 1: 570 × 365 = 208,050 rows; gauge 2:
  184 × 365 = 67,160 rows.

### Bytes

- **Bytes per row:** 319,488 ÷ 754 = **about 424 bytes**, indexes included. L-REFSIZE flags this as an
  upper-ish bound, not a constant: at 754 rows, rounding to whole pages inflates it. A table of a
  year's rows would show the real figure.
- **Per year:** 275,210 rows × 424 bytes ≈ 116.6 MB = **about 0.11 GiB**, for the 2 gauges now in the
  database, as an upper-ish bound.

### Per-place scaling: a gap

It can't be computed from the 2 measured places. `place_water_gauges` and `place_context_cache` are
both 0 rows, so no reference row is linked to a place, and the measurement gives no reference rows per
place. Two places sharing 2 gauges, 1 weather station and 16 soil map units can't be split into a
per-place figure. **So there is no 1 / 5 / 20-place projection on this page.** It moves to
[NOT YET MEASURABLE](#3-not-yet-measurable).

## 3. NOT YET MEASURABLE

No numbers here, on purpose.

| What | Why it has no number | The run that would measure it |
| --- | --- | --- |
| **iNaturalist volume and growth** (`inat_observations`, `inat_taxa`) | 0 rows. The iNat sync has never run on the dev database. | The first real iNat ingest, then L-REFSIZE again. |
| **Rows and GiB per place; the 1 / 5 / 20-place projection** | No place-to-reference links exist yet (0 rows in `place_water_gauges` and `place_context_cache`), so nothing can be divided per place. | L-REFSIZE again after the place links are written, with more than 2 places seeded. |
| **NOAA and USDA steady-state growth** (`weather_normals`, `weather_stations`, `soil_map_units`) | One run each. A repeat run may overwrite, add or do nothing, and no second run exists to show which. | L-REFSIZE again after the first fortnight of scheduled sync runs. |
| **Observed `water_readings` growth** | One run. The figures in section 2 are derived, not observed. | The same fortnight of scheduled runs: the weekly delta from `observed_at` / `fetched_at`. |
| **Stack B** | Not measured. | L-REFSIZE on stack B, if it is to be counted. |

**Follow-up (ecofolk#1107):** re-run L-REFSIZE after the first real iNat ingest and the first
fortnight of scheduled sync runs, then update this page and [`cost-model.csv`](cost-model.csv) from it.

## Cost

Prices from [`cost-model.csv`](cost-model.csv), Montréal, read 2026-10-14:

- Cloud SQL SSD storage: **$0.187 / GiB-month** (`sql-storage`).
- Cloud SQL backups: **$0.088 / GiB-month** (`sql-backups`).

**Storage.** The disk is provisioned, not used: `disk_size` is unset, so the instance gets the
provider's 10 GiB minimum, and the `sql-storage` line already bills all 10 GiB ($1.87 a month) however
full it is. Reference data adds to the bill only once the disk fills and autoresize grows it.

| Figure | Volume | Class | Share of the 10 GiB disk | Added to the bill |
| --- | --- | --- | ---: | ---: |
| Reference tables now | 1,160 kB (0.0011 GiB) | measured | 0.01% | $0.00 |
| Whole database now | 22 MB | measured | 0.2% | $0.00 |
| `water_readings` after one year, 2 gauges | about 0.11 GiB | derived, not observed | about 1.1% | $0.00 |
| iNat; per-place growth | — | not yet measurable | — | — |

**What it would cost if billed per GiB** (it isn't, inside the provisioned disk; this shows the scale):
0.11 GiB × $0.187 ≈ $0.02 a month of storage, and if every backup held it in full, 0.11 GiB × $0.088 ≈
$0.01 a month of backups. Both are derived from the derived volume, and both round to cents the cost
model already carries: the `sql-backups` line assumes 0.5–2 GiB of backups.

**Disk fit.** The measured database plus the derived year is under 0.15 GiB, against 10 GiB. It fits
with no retention window. The cost model's tier and disk stay as they are.

**Memory fit.** At 22 MB, the whole measured database is small enough that any Cloud SQL tier caches
it. The cost model's tier is `db-f1-micro` (`modules/cloudsql`'s default). This session couldn't reach
Google's Cloud SQL documentation to cite that tier's memory, so this page states no figure for it.
Recheck it against the instance settings page when iNat's volume is known, since that is the only
table likely to change the answer.

**Retention.** No retention window is needed for what is measured or derived. `water_readings` is the
one table that grows without limit; at the derived rate it reaches 1 GiB in roughly 9 years for the
current 2 gauges (1 ÷ 0.11). That changes with the number of gauges, which is part of the per-place gap.
Decide on a window when L-REFSIZE is re-run, not before.

## How this feeds the cost model

`cost-model.csv` carries a `sql-reference-data` line at $0.00 in every scenario. It makes no change to
the totals: the volume is inside the `sql-storage` line's 10 GiB and the `sql-backups` line's
allowance. When ecofolk#1107's re-measure lands, update the line's usage, and if the volume (iNat
included) passes what the 10 GiB disk holds, raise `sql-storage` too.
