# Cost model: a month of 20 users after the $300 credit

ecofolk-infra#28. Prices read **2026-10-14**, in USD, for `northamerica-northeast1` (Montréal) wherever
the price depends on region. The line-by-line data, with every unit price, source and assumption, is
[`cost-model.csv`](cost-model.csv); this page is the summary, and its totals are the CSV's `TOTAL` row.

## The number

**About $10.95 a month without C14's off-hours stop, about $8.23 with it, for 20 active users.** Most of it
is the Cloud SQL instance, which bills by the hour whether anyone uses the app or not. The next-largest
lines are now media: Cloud Run egress (the API serves every media view) and the GCS media bucket's
operations, neither of which a free tier covers in full.

| Monthly cost after the credit (USD) | Idle (0 users) | 20 active users | 2× headroom (40-user load) |
| --- | ---: | ---: | ---: |
| Without C14 (SQL up 24 h) | 10.44 | **10.95** | 11.63 |
| With C14 (SQL up 16 h/day) | 7.72 | **8.23** | 8.91 |
| Before free tiers, without C14 (gross) | 50.21 | 52.12 | 54.20 |

- **Against the $25 dev budget (#15):** fits in every scenario, with or without C14. At 20 users the headroom is
  about $14.05 without C14 and about $16.77 with it; at 2× it is about $13.37 and $16.09.
- **Against the $100–150 MVP budget:** well under it, at about a tenth of the low end. Everything this
  page does *not* model (see [Not modelled](#not-modelled)) has to fit in the remaining roughly $89–139.
- **Usage moves the total only a little.** Going from idle to 2× headroom adds about $1.19, nearly all of
  it media: Cloud Run egress for media views and GCS Class A operations. The bill is still set by what
  runs, not by how many people use it.
- **The free tiers carry about $41 a month.** The gross row is what these same lines would cost with no
  free allowance. Almost all of the difference is the uptime check (see
  [Lines where a free tier is doing the work](#lines-where-a-free-tier-is-doing-the-work)).
- **The credit runs out by date, not by spend.** At about $10.95 a month, 90 days uses roughly $32 of the
  $300. The figures above are what each month costs once the credit has expired.

## Line by line

Net of free tiers, USD per month. "C14" means Cloud SQL stopped out of hours. Lines are rounded to the cent,
and each total is the sum of the rounded lines.

| Line | Configured in this repo? | Idle | Idle, C14 | 20 users | 20 users, C14 | 2× | 2×, C14 | Free tier doing the work? |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Cloud SQL instance (db-f1-micro, zonal) | yes, `modules/cloudsql` | 8.47 | 5.65 | 8.47 | 5.65 | 8.47 | 5.65 | no |
| Cloud SQL storage (10 GiB SSD) | yes, `disk_size` unset | 1.87 | 1.87 | 1.87 | 1.87 | 1.87 | 1.87 | no |
| Cloud SQL backups | yes, `backup_configuration` | 0.04 | 0.04 | 0.09 | 0.09 | 0.18 | 0.18 | no |
| Cloud SQL public IPv4 | yes, `ipv4_enabled = false` | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | no (no public IP) |
| Cloud Run CPU | yes, `modules/cloudrun_api` | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | **yes** |
| Cloud Run memory | yes | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | **yes** |
| Cloud Run requests | yes | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | **yes** |
| Cloud Run egress to internet (API + media views) | yes | 0.00 | 0.00 | 0.30 | 0.30 | 0.73 | 0.73 | **partly** (first 1 GiB) |
| Cloud Run → Cloud SQL traffic | yes, `modules/network` | 0.00 | 0.00 | 0.01 | 0.01 | 0.01 | 0.01 | no |
| VPC, subnet, PSA peering | yes, `modules/network` | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | no (no charge) |
| Artifact Registry storage | module yes, not yet called by an environment | 0.05 | 0.05 | 0.05 | 0.05 | 0.05 | 0.05 | **partly** (0.5 GiB) |
| Cloud Logging (#6) | no | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | **yes** |
| Uptime check (#5) | no | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | **yes** |
| Cloud Scheduler jobs (#2, #14, #17) | no | 0.00 | 0.10 | 0.00 | 0.10 | 0.00 | 0.10 | **yes** (3 jobs) |
| Identity Platform (#20) | yes, `modules/auth` | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | **yes** |
| GCS media storage, Standard, Montréal (#21) | yes, `modules/media_bucket` | 0.01 | 0.01 | 0.06 | 0.06 | 0.10 | 0.10 | no (Always Free is US-only) |
| GCS soft-deleted bytes (7 days) | yes, `soft_delete_policy` | 0.00 | 0.00 | 0.00 | 0.00 | 0.01 | 0.01 | no |
| GCS Class A operations | yes, `modules/media_bucket` | 0.00 | 0.00 | 0.10 | 0.10 | 0.20 | 0.20 | no |
| GCS Class B operations | yes, `modules/media_bucket` | 0.00 | 0.00 | 0.00 | 0.00 | 0.01 | 0.01 | no |
| Firebase Hosting storage (#22) | module in PR #51, not yet merged | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | **yes** (10 GB) |
| Firebase Hosting data transfer (#22) | module in PR #51, not yet merged | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | **yes** (360 MB/day) |
| **Total** | | **10.44** | **7.72** | **10.95** | **8.23** | **11.63** | **8.91** | |

C14 moves two lines: the SQL instance falls to 16 of 24 hours, and Scheduler gains C14's two jobs (stop
and start). Those make 4 jobs against a free allowance of 3, so with C14 one job costs $0.10. Storage and
backups bill the same whether the instance is running or stopped.

"Configured in this repo? no" means the resource is in the spec's list but nothing in this repo creates
it yet. Its usage comes from an assumption, not from HCL. Recheck those lines when their rows land.
The Firebase Hosting lines follow `modules/web_hosting` as PR #51 proposes it; that module is not on `main` yet.

Media never leaves through the bucket. The API proxies `GET /media` (ecofolk#377), so the bucket only
pays storage and operations: GCS → Cloud Run in the same region is free, and each byte a user views is
billed once, on the Cloud Run egress line.

## Lines where a free tier is doing the work

Gross is the cost of the 20-user, no-C14 usage at the paid rate, before any free allowance.

| Line | Free allowance | 20-user usage | Gross without the allowance |
| --- | --- | --- | ---: |
| **Uptime check** | 1M executions per project per month | 131,400 | **39.42** |
| Cloud Run CPU | 180,000 vCPU-s per billing account (worth $4.32 at us-central1 rates) | 18,000 vCPU-s | 0.60 |
| Cloud Logging | 50 GiB per project per month | 1 GiB | 0.50 |
| Scheduler | 3 jobs per billing account | 2 jobs (4 with C14) | 0.20 (0.40 with C14) |
| Cloud Run egress | 1 GiB to North America per month | 3.53 GiB (1.14 API + 2.38 media) | 0.42 (0.30 is paid) |
| Firebase Hosting | 10 GB stored; 360 MB/day transferred | 0.15 GB; 0.8 GB/month, 40 MB peak day | 0.12 |
| Identity Platform | 50,000 MAU (email sign-in) | 20 MAU | 0.11 (at the first paid tier's rate) |
| Artifact Registry | 0.5 GiB per billing account | 1 GiB | 0.10 (0.05 is paid) |
| Cloud Run memory, requests | 360,000 GiB-s; 2M requests | 9,000 GiB-s; 60,000 | 0.05 |

The uptime check is the only free tier carrying real money. One check every minute from three checker
regions uses 13% of the per-project allowance. A second project (prod) gets its own million, but every
extra check or shorter period counts against it. The Cloud Run, Scheduler and Artifact Registry
allowances belong to the **billing account**, so a prod project on the same billing account shares them
with dev.

**Cloud Run egress is no longer fully covered.** Media views put it over the 1 GiB allowance at 20 users
(3.53 GiB) and well over at 2× (7.06 GiB). It is the line that grows fastest with real use.

**No free tier applies to the GCS media bucket.** Cloud Storage's Always Free allowance (5 GB-months of
Standard storage, 5,000 Class A and 50,000 Class B operations) applies only to usage in US-WEST1,
US-CENTRAL1 and US-EAST1 (<https://cloud.google.com/storage/pricing>, "Cloud Storage Always Free usage
limits", footnote 1, read 2026-10-14). The bucket is in NORTHAMERICA-NORTHEAST1, so every GCS line is
paid from the first byte and operation.

## Assumptions

Every number above comes from one of these. Each one is also on its line in the CSV's `assumption` column.

1. **One environment, as configured in `environments/dev`.** That is the only root that creates
   resources. `environments/prod` only enables APIs today. A prod copy of the same stack would add the
   three Cloud SQL lines again, about $10.43 a month without C14. Free tiers per billing account would
   then be shared, not doubled. That copy is **not** in the totals.
2. **A month is 730 hours**, which is Google's own conversion.
3. **C14's schedule:** C14 isn't defined in this repo, so this assumes Cloud SQL runs 07:00–23:00
   America/Toronto every day, 486.67 h a month. A weekdays-only schedule would cut the instance line
   further.
4. **20 active users:** 20 days a month, 150 API calls a day each, which is 60,000 requests a month. 2×
   headroom is 120,000. Idle is zero requests.
5. **Cloud Run** runs at the module's defaults: `limits` unset, so 1 vCPU and 512 MiB. Concurrency is 80
   (the provider default for 1 vCPU), but no overlap between requests is assumed. `cpu_idle = true`
   means request-based billing. Billed instance time is 0.3 s per request, enough to cover cold starts.
   Responses average 20 KiB.
   **Media views** are separate from uploads: each active user views 500 media items a month (25 a day
   over 20 active days) at 250 KiB on average, which is 2.38 GiB at 20 users and 4.77 GiB at 2×. The
   API proxies every view, so all of it is Cloud Run internet egress. No credit is taken for the
   `private, max-age=300` browser cache, which makes this an upper estimate.
6. **Cloud Run free tier:** Google applies it as a spending discount at us-central1 rates. It is worth
   $4.32 of CPU, $0.90 of memory and $0.80 of requests a month, set against Montréal-priced usage.
7. **Cloud SQL:** `tier` defaults to `db-f1-micro`, ZONAL, ENTERPRISE edition. `disk_size` is unset, so
   it gets the provider's minimum of 10 GB, PD_SSD, with autoresize on (which only grows when the disk
   fills). Backups are on with the default 7 retained, using 0.5 / 1 / 2 GiB across the three
   scenarios. There is no public IP, so there is no idle-IPv4 charge. Tier and disk stay the same in
   all three scenarios: 2× load is still well inside one f1-micro.
8. **Cloud Run → Cloud SQL traffic:** 10 KiB per request, all of it priced as crossing zones at
   $0.01/GiB, which is the worst case. Same-zone traffic is free.
9. **Artifact Registry:** about 1 GiB of unique image layers, kept there by the module's cleanup
   policies (keep the 10 newest, delete untagged images after 7 days). Pulls by Cloud Run in the same
   region are free. The module is not yet called from `environments/dev`.
10. **Logging (#6):** the default `_Default` bucket with 30-day retention, so there is no retention
    charge. Ingestion is 0.2 / 1 / 2 GiB a month.
11. **Uptime (#5):** one check on the API, every 1 minute, from the minimum of 3 checker regions. That is
    131,400 executions a month in every scenario.
12. **Scheduler:** one job for #2, one for #17, and two for C14 (#14, stop and start). That is 2 jobs
    without C14 and 4 with it. A paused job still counts.
13. **Identity Platform:** email and password only, as `modules/auth` configures it, so each user is a
    Tier 1 MAU. Anonymous sign-in is off. No phone, SMS or MFA, which bill per message.
14. **GCS media bucket (#21)**, as `modules/media_bucket` configures it: Standard class, regional
    NORTHAMERICA-NORTHEAST1, uniform access, no versioning, one AbortIncompleteMultipartUpload rule
    (1 day) and no age-based delete. Stored: 0.5 GiB of seed content plus 0.1 GiB (about 100 MiB) of
    uploads per user, so 0.5 / 2.5 / 4.5 GiB. Operations: 1,000 Class A (uploads, multipart parts,
    lists, metadata writes) per active user a month, and one Class B object read per media view (500
    per active user). **Soft delete** keeps deleted bytes for 7 days and bills them at the Standard
    rate: the app's sweep (ecofolk#310) is assumed to remove 0.025 GiB per active user a month, so
    0.5 GiB deleted at 20 users is 0.115 GiB-month of soft-deleted storage. Prices are the
    single-region, flat-namespace rates.
15. **Firebase Hosting (#22)**, as `modules/web_hosting` (PR #51) proposes it: one site serving a static
    build of about 5 MB, with 30 retained releases (0.15 GB stored). One 2 MB cold load per active
    user per active day (cache hits count toward transfer too): 0.8 GB a month at 20 users, 40 MB on
    the busiest day, against 360 MB a day free.
16. **USD, before tax.** Any tax, and the conversion if the billing account is invoiced in CAD, comes on
    top.

## Prices (read 2026-10-14)

| Line | Unit price (USD) | Source |
| --- | --- | --- |
| Cloud SQL db-f1-micro, Montréal | $0.0116 / hour ($8.468 / month) | <https://cloud.google.com/sql/pricing> |
| Cloud SQL SSD storage, Montréal | $0.187 / GiB-month | <https://cloud.google.com/sql/pricing> |
| Cloud SQL backups, Montréal | $0.088 / GiB-month | <https://cloud.google.com/sql/pricing> |
| Cloud SQL idle public IPv4, Montréal | $0.011 / hour | <https://cloud.google.com/sql/pricing> |
| Cloud Run CPU, request-based, Montréal | $0.0000336 / vCPU-s | <https://cloud.google.com/run/pricing> |
| Cloud Run memory, request-based, Montréal | $0.0000035 / GiB-s | <https://cloud.google.com/run/pricing> |
| Cloud Run requests | $0.40 / million | <https://cloud.google.com/run/pricing> |
| Internet egress from Montréal to North America (Premium tier, first TiB) | $0.12 / GiB | <https://cloud.google.com/vpc/network-pricing> |
| Inter-zone traffic, same region | $0.01 / GiB | <https://cloud.google.com/vpc/network-pricing> |
| Artifact Registry storage | $0.10 / GiB-month after 0.5 GiB | <https://cloud.google.com/artifact-registry/pricing> |
| Cloud Logging ingestion | $0.50 / GiB after 50 GiB | <https://cloud.google.com/stackdriver/pricing> |
| Uptime-check executions | $0.30 / 1,000 after 1M | <https://cloud.google.com/stackdriver/pricing> |
| Cloud Scheduler | $0.10 / job / 31 days after 3 jobs | <https://cloud.google.com/scheduler/pricing> |
| Identity Platform, Tier 1 (email) | $0 up to 50,000 MAU, then $0.0055 / MAU | <https://cloud.google.com/identity-platform/pricing> |
| Cloud Storage Standard, regional, Montréal | $0.023 / GiB-month, no Always Free in this region | <https://cloud.google.com/storage/pricing> |
| Cloud Storage Class A / Class B, single region, Standard | $0.005 / $0.0004 per 1,000 operations | <https://cloud.google.com/storage/pricing> |
| Cloud Storage → Cloud Run, same region | free | <https://cloud.google.com/storage/pricing> |
| Firebase Hosting storage | $0.026 / GB after 10 GB | <https://firebase.google.com/pricing>\* |
| Firebase Hosting data transfer | $0.15 / GB after 360 MB/day | <https://firebase.google.com/pricing>\* |

\* firebase.google.com could not be reached from the session that wrote this model. The two Firebase
Hosting prices come from Google's search-indexed copy of that page and of
<https://firebase.google.com/docs/hosting/usage-quotas-pricing>. Recheck them against the live page.
Both lines are $0 in every scenario, so the totals don't depend on them.

## Check against live billing first

When #5176's billing feed exists, compare these lines first, biggest risk first:

1. **Cloud SQL instance (SKU: db-f1-micro, Montréal).** The largest line. Confirm it bills at
   about $0.0116 an hour ($8.47 over 730 h). With C14 running, also confirm the instance-hours are
   close to 487, not 730.
2. **Cloud SQL storage.** Confirm the disk is still 10 GiB, and that autoresize hasn't grown it.
3. **Cloud Storage, media bucket.** Stored GiB (live plus soft-deleted) and Class A / Class B
   operation counts against assumption 14. No free tier applies in Montréal, so every unit bills.
4. **Cloud Run internet egress.** GiB out against the 3.53 GiB assumption (1.14 API, 2.38 media). It
   is already past its 1 GiB free allowance and is the line most likely to move with real media use.
5. **Cloud Run CPU.** Billed vCPU-seconds against the 0.3 s/request assumption. It still sits inside
   its free tier, but media proxying adds instance time the 0.3 s figure may not cover.
6. **Monitoring uptime-check executions.** Make sure they stay under 1M per project. This line is worth
   $39 a month if the free tier stops covering it.
7. **Cloud Scheduler.** The job count across the whole billing account, since the 3 free jobs are
   shared by every project on it.

## Not modelled

Out of the spec's scope, or not yet built. Each could change the total, and none is in it:

- **Vertex AI usage, including grounding.** `aiplatform.googleapis.com` is enabled, but model calls are
  per token, and grounding with Google Search is billed per request. At 20 users this could be the
  largest line on the bill. Model it when the app's AI usage is known.
- Cloud Build minutes and deploy CI (ef#408), Secret Manager secrets (ef#399), a custom domain or load
  balancer (ef#404/#670), and the Terraform state bucket.
- A second, prod environment (see assumption 1).
- Live billing data (#5176).

## Updating this model

`cost-model.csv` is the data. Each line has its unit, price, source URL, the date the price was read,
its free allowance and its assumption. Its cost columns are `<scenario>_no_c14`, `<scenario>_c14` and
`<scenario>_gross_no_c14`, for the scenarios `idle`, `users20` and `headroom2x`. The `TOTAL` row is the
sum of the line rows, and the tables above repeat those totals. Change a price or an assumption in the
CSV first, recompute the totals, then update this page to match.
