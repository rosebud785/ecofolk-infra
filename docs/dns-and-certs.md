# DNS and certificates: who holds the domain, and what happens when the cert expires

**Status: FINALISED for Andy's decision (#23, 2026-10-14).** Finalised by the Documenter from the
reviewed draft (PR #50). Nothing is decided until Andy fills in [§4](#4-andy-decides). Nothing here buys anything, creates a DNS
record or adds Terraform.

Facts were checked on 2026-10-14. Every factual claim cites a vendor page. The [Sources](#sources) table
says how each page was read; a few Google pages are still only search excerpts (see
[Verification gaps](#verification-gaps)).

What this record covers:

- the web app on **Cloudflare Pages**;
- the API on **Cloud Run** (`modules/cloudrun_api/`) in `northamerica-northeast1` (Montréal), as
  required by this repo's region pin (`scripts/check-region-pin.sh`).

---

## 1. Options for who holds the domain

Both options put DNS on Cloudflare. They differ only in **who is the registrar**.

### Option A: Cloudflare Registrar (DNS in the same account)

- **Cost:** Cloudflare charges only what the registry and ICANN charge, with no markup [CF-REG].
  Fees are non-refundable once the registration, renewal or transfer completes [CF-FAQ].
- **DNS is tied to the registrar:** every domain on Cloudflare Registrar uses Cloudflare nameservers. To
  use other nameservers you have to move the domain to another registrar first [CF-FAQ]. Cloudflare
  Registrar requires a full DNS setup on Cloudflare, and you cannot use another DNS provider while the
  domain is registered there [CF-XFER-IN].
- **Renewal:** auto-renew is on by default, and renewal is at the registry's list price [CF-REG].
  Cloudflare tries to auto-renew about 30 days before expiry and retries three more times before you
  have to renew by hand [CF-FAQ].
- **Lock and transfer out:** to leave, you unlock the domain in the dashboard and copy the auth code.
  If you don't approve the transfer out by hand, it auto-approves on the fifth day. If you reject it,
  Cloudflare puts the registrar lock back [CF-XFER-OUT].
- **Account-role risk:** anyone with Super Administrator or Administrator rights on a zone can manage
  the domain, which includes unlocking it and getting the transfer auth code [CF-XFER-OUT]. Under
  Option A, those account roles are effectively control of the domain.
- **Getting there (registering new):** there's nothing to transfer. ICANN's 60-day rule still applies:
  the domain can't be transferred out within 60 days of registration [CF-XFER-OUT].
- **Getting there (transferring in an existing name):** the domain has to be active on Cloudflare DNS
  before you can enter an auth code [CF-XFER-IN]. Before the transfer:
  - turn off DNSSEC at the old registrar and wait at least 24 hours before changing nameservers;
  - remove the old registrar's lock (`clientTransferProhibited`).

  You can re-enable DNSSEC through Cloudflare after the transfer [CF-XFER-IN]. The transfer is blocked
  for 60 days after a registration, a previous transfer, or a change to the registrant name,
  organisation or email [CF-XFER-IN]. Most gTLD transfers add one year to the term. Some ccTLDs don't
  [CF-XFER-IN] [CF-FAQ]. The transfer takes up to 10 days [CF-XFER-IN].
- **TLDs:** over 400 are supported, and the full list is on the TLD policies page [CF-TLD]. `.ca`
  appears on that list [CF-TLD-POLICY] (read from a search excerpt only; check it when Andy picks the
  name).
- **If it lapses:** Cloudflare gives a 40-day grace period for most TLDs. The domain keeps resolving
  for the first 30 days, then shows a suspension page. A 30-day redemption period follows (a restore
  fee may apply), then 5 days pending delete, then the name is released [CF-FAQ].

### Option B: another registrar, with Cloudflare DNS

- **Cost and renewal:** set by the other registrar's terms, which this draft hasn't checked because no
  registrar has been named. Andy fills it in under §4.
- **DNS:** Cloudflare DNS still works. You point the nameservers at the other registrar to the ones
  Cloudflare assigns [CF-NS]. The registrar and the DNS provider can then change independently: you can
  leave Cloudflare DNS without a registrar transfer, which Option A doesn't allow [CF-FAQ].
- **Lock:** the registrar lock and auth code stay with the other registrar. Most registrars lock by
  default, and some have several lock types that each have to be turned off [CF-XFER-IN]. Account
  security has two halves: the registrar account controls the domain, and the Cloudflare account
  controls DNS and certificates.
- **DNSSEC:** if the other registrar has DNSSEC on for its own DNS, turn it off before moving the
  nameservers to Cloudflare. Otherwise resolution fails [CF-XFER-IN].
- **Moving to Option A later:** possible, once the name is at least 60 days old and hasn't been
  transferred or had a registrant change in the last 60 days [CF-XFER-IN].
- **Watch for:** some platforms that host and register at once (Shopify, Block, Wix are named) don't
  allow nameserver changes. Cloudflare's workaround is to transfer to an ordinary registrar first and
  wait 60 days [CF-XFER-IN].

### Side by side

| | A: Cloudflare Registrar | B: other registrar + Cloudflare DNS |
| - | - | - |
| Registration price | at cost, no markup [CF-REG] | the other registrar's price (not assessed) |
| Can DNS move off Cloudflare without a transfer? | No [CF-FAQ] | Yes [CF-NS] |
| Accounts that control the domain | one (Cloudflare) [CF-XFER-OUT] | two (registrar + Cloudflare) |
| Auto-renew | on by default [CF-REG]; tries ~30 days before expiry [CF-FAQ] | the other registrar's terms |
| Transfer lock after registering or transferring | 60 days, ICANN [CF-XFER-OUT] | 60 days, ICANN [CF-XFER-IN] |

---

## 2. Certificates under each option

Both options use Cloudflare DNS, so the certificate story is the same for A and B. Only the API's path
changes it.

### 2.1 Web app on Cloudflare Pages: automatic certificate

- **Custom domains:**
  - an apex domain (`example.com`) must be a Cloudflare zone on the same account as the Pages project
    [CF-PAGES];
  - a subdomain only needs a CNAME to `<site>.pages.dev`, added through the Pages *Custom domains*
    flow. A CNAME added by hand without that flow fails with a 522 error [CF-PAGES].
- **Certificate issuance:** Cloudflare issues the certificate for the custom domain itself. The only
  known issue the Pages docs list is CAA records that don't allow Cloudflare's CAs [CF-PAGES].
- **Renewal:** Universal SSL certificates are free and issued automatically for proxied hostnames, and
  Cloudflare handles issuance, renewal and deployment [CF-USSL]. They're valid for 90 days, and
  auto-renewal starts 30 days before expiry [CF-VALIDITY].
  - Note for the Documenter: the Pages page doesn't name the certificate type it issues. The Universal
    SSL renewal figures above are the zone-level behaviour.
- **If renewal fails:** Cloudflare keeps trying until 24 hours before expiry. If another valid
  certificate exists for the hostname, Cloudflare deploys that one in the last 24 hours [CF-VALIDITY].

### 2.2 API on Cloud Run

**`run.app`.** The default `*.run.app` URL is HTTPS-only. Google's front end terminates TLS, so the
container never handles certificates [GCP-RUN-SEC] [GCP-RUN-HTTPS]. Google owns this certificate. We
don't renew it and can't.

**The region question: are Cloud Run domain mappings available in `northamerica-northeast1`? No.**
Cloud Run's locations page lists the regions where domain mapping is available. The ten listed are:

`asia-east1`, `asia-northeast1`, `asia-southeast1`, `europe-north1`, `europe-west1`, `europe-west4`,
`us-central1`, `us-east1`, `us-east4`, `us-west1`.

`northamerica-northeast1` isn't one of them. It's a Cloud Run region, listed under Tier 2 pricing
[GCP-RUN-LOC]. The custom-domain page gives the same ten regions and says other regions must use one of
the other mapping options [GCP-RUN-MAP]. That page also labels domain mapping *Limited availability*
and *Preview*. It says domain mapping isn't production-ready because of latency issues, isn't supported
at General Availability, and isn't recommended for production [GCP-RUN-MAP].

**So domain mapping is out on two counts:** it's unavailable in our region, and it isn't
production-ready anyway. That leaves the two alternatives in the spec.

#### 2.2a Cloudflare-proxied CNAME to `run.app`

- **What it is:** a proxied (orange-cloud) CNAME, for example `api.<domain>`, pointing at the
  service's `run.app` hostname.
- **The catch, from Cloudflare's own docs:** Cloud Run may reject requests with a 404 or 400 when the
  `Host` header doesn't match a domain configured on the endpoint, and Cloudflare sends the original
  custom hostname as `Host` by default. The documented fixes are:
  1. make Cloud Run accept the custom hostname, which in our region means a load balancer (§2.2b);
  2. override `Host` with an Origin Rule [CF-ORIGIN-CLOUD].
- **Plan limits on the fix:** overriding `Host` in an Origin Rule is **Enterprise only**. It's "No" on
  Free, Pro and Business [CF-ORIGIN-RULES]. Snippets aren't available on Free [CF-SNIPPETS].
- **Free-plan route that remains:** a Cloudflare Worker on the API hostname that calls `fetch()` on the
  `run.app` URL [CF-WORKERS-FETCH].
  - The Workers Free plan gives 100,000 requests a day [CF-WORKERS-PRICING].
  - The Workers Paid plan has a $5 USD/month minimum per account [CF-WORKERS-PRICING].
  - That's extra code to own (the Worker), and it is not Terraform in this repo.
- **Certificates:**
  - The visitor-facing certificate is Cloudflare's: automatic, as in §2.1 [CF-USSL] [CF-VALIDITY].
  - The Cloudflare-to-origin leg uses Google's `run.app` certificate, which Google manages
    [GCP-RUN-SEC].
  - We renew nothing.
- **Ingress and IAM:** this path needs the service publicly reachable on `run.app`.
  `modules/cloudrun_api/` already sets `ingress = "INGRESS_TRAFFIC_ALL"`, and its comments note the
  `allUsers` invoker binding is a local follow-up there, not here. As a result, `run.app` stays
  directly reachable alongside the custom domain.
- **Monthly cost:** $0 within the Workers Free allowance. $5/month minimum on Workers Paid
  [CF-WORKERS-PRICING].
- **Data residency (Architect's note):** a proxied API hostname means every API request and response,
  including auth tokens and media proxied through `GET /media`, is **decrypted at Cloudflare's edge,
  which can be outside Canada**. The region pin covers GCP resources, not the transit path, so this is
  a fact for Andy to weigh, not a pin violation. 2.2b terminates TLS in Montréal.
- **Upload size:** Cloudflare's proxied request-body limit is set by the account plan: **100 MB on
  Free and Pro, 200 MB on Business**, and 413 above that [CF-LIMITS]. The app's largest upload is the
  **20 MiB** audio cap (`AUDIO_MAX_BYTES` in `packages/shared/src/media.ts`; images 10 MiB), so
  the Free plan has room. 2.2b has no such edge limit.

#### 2.2b Google load balancer (regional external Application Load Balancer + serverless NEG)

- **What it is:** a load balancer with a serverless NEG backend pointing at the Cloud Run service. The
  NEG and the load balancer must be in the same region as the service [GCP-LB-REGIONAL]. A regional
  load balancer keeps everything in `northamerica-northeast1`.
  - Google's custom-domain page recommends the *global* external Application Load Balancer
    [GCP-RUN-MAP]. A global load balancer is outside this repo's Montréal-only region pin. Using it
    would need an explicit exception from the Architect, and this draft doesn't propose one.
- **Certificates:** Certificate Manager issues and renews Google-managed certificates automatically,
  and its overview lists the regional external Application Load Balancer as a supported target
  [GCP-CERTMGR]. We renew nothing.
- **Ingress:** Cloud Run ingress can then be limited to internal and Cloud Load Balancing traffic, so
  `run.app` stops being directly reachable [GCP-LB-REGIONAL].
- **Monthly cost:** at least about **$18.25/month** before traffic, from **forwarding rules**:
  - Google charges $0.025/hour for the first five forwarding rules, which is $0.025 × 730 h ≈ $18.25
    [GCP-LB-PRICE];
  - **data processing** is charged per GiB by region on top of that. The excerpts show
    $0.008–$0.012/GiB, but the Montréal row hasn't been confirmed [GCP-LB-PRICE] [GCP-LB-PRICE-ANN];
  - whether a separate **proxy-instance** charge applies to the regional external ALB hasn't been
    confirmed. The excerpt only showed one ($0.025/hour, three-instance minimum) for the *internal*
    ALB [GCP-NET-PRICE]. Both are still unconfirmed (see Verification gaps); confirm them before Andy compares costs.
- This option would be Terraform plus IAM later, and is out of scope here.

#### API options at a glance

| | 2.2a Cloudflare proxy + Worker | 2.2b regional external ALB |
| - | - | - |
| Works in `northamerica-northeast1` | yes; it's just HTTPS to `run.app` | yes, in-region [GCP-LB-REGIONAL] |
| Visitor certificate | Cloudflare, automatic [CF-USSL] | Google-managed, automatic [GCP-CERTMGR] |
| `run.app` still public | yes | can be closed [GCP-LB-REGIONAL] |
| Where TLS terminates | Cloudflare's edge, possibly outside Canada | Montréal |
| Request-body limit | 100 MB on Free [CF-LIMITS]; app max is 20 MiB, so it fits | none at the edge |
| Monthly cost | $0 (Free, ≤100k req/day) or $5 min [CF-WORKERS-PRICING] | ≥ ~$18.25 + data processing (+ proxy charge, unconfirmed) [GCP-LB-PRICE] |
| New moving part | a Worker | LB + NEG + certificate (Terraform) |

---

## 3. What happens when the cert expires

Every certificate in every option renews automatically. Nobody on the team renews anything by hand.
The risk isn't a forgotten renewal. It's a renewal that **fails silently**, for example because of:

- a CAA record that blocks the CA [CF-PAGES];
- a broken DCV on a partial setup [CF-VALIDITY];
- a DNS change that deactivates the Pages domain [CF-PAGES].

| Certificate | Option | Who renews | How |
| - | - | - | - |
| Web app (Pages custom domain) | A and B | Cloudflare | automatic: 90-day certificate, renewal from 30 days before [CF-VALIDITY] |
| API, visitor side, via Cloudflare proxy | 2.2a | Cloudflare | automatic, same as above [CF-USSL] |
| API, `run.app` (origin for 2.2a, also direct) | all | Google | automatic; Google's front end terminates TLS [GCP-RUN-SEC] |
| API via load balancer | 2.2b | Google (Certificate Manager) | automatic [GCP-CERTMGR] |
| Domain registration (not a cert, same outage) | A | Cloudflare | auto-renew on by default, first try ~30 days before expiry, 3 retries [CF-FAQ] |
| Domain registration | B | other registrar | that registrar's terms (not assessed) |

### Detection: C5's uptime checks (#5)

- **Uptime checks:** Cloud Monitoring uptime checks on the web root and on the API's `/health` (the
  scope of #5), with **SSL certificate validation on**. With validation on, the uptime check records
  `monitoring.googleapis.com/uptime_check/time_until_ssl_cert_expires` [GCP-UPTIME] [GCP-UPTIME-CHARTS].
- **Alert:** an alerting policy on that metric when it drops **below 14 days**.
  - Cloudflare starts renewing at 30 days [CF-VALIDITY], so a 14-day alert means automatic renewal has
    been failing for over two weeks. That's a real signal, with time left to fix it.
  - Google-managed certificates: Certificate Manager says it can automatically issue and renew them
    [GCP-CERTMGR], but the page states **no validity period or renewal window**, so this record does
    not claim 90 days for them. The 14-day alert is the safety net either way.
- **What the check actually sees:** an uptime check sees the certificate the **visitor** sees.
  - Under 2.2a, that's Cloudflare's edge certificate, not `run.app`'s.
  - `run.app` is Google's own certificate on Google's own domain, so watching it is optional.
- **What it can't catch:** the **domain registration** lapsing. No certificate check will show that
  before the domain stops resolving. Registrar renewal is covered by auto-renew and the registrar's
  expiry emails [CF-FAQ], not by #5.

**Follow-up to #5:** C5 hasn't merged (#5 is open, with no PR, as of 2026-10-14), so per the spec no
follow-up was posted. #5 should pick this up as written:

> Enable SSL validation on both uptime checks, and alert when `time_until_ssl_cert_expires` < 14 days.

---

## 4. Andy decides

Left blank on purpose. Nothing in §1–§3 is final until these are filled.

| Decision | Choice | Decided by | Date |
| - | - | - | - |
| Domain name (ecofolk#670) | | Andy | |
| Registrar: A (Cloudflare Registrar) or B (name the registrar) | | Andy | |
| API path (2.2a or 2.2b) | | Architect recommends; Andy approves any recurring spend | |

**API path.** The spec did not reserve this choice, but 2.2b costs roughly $18+/month recurring and
recurring spend is Andy's call, so it has a row. **Architect's recommendation: 2.2a for pre-launch dev,
revisited at go-live**, once the residency and upload-size facts above and the 2.2b price (still
unconfirmed, see Verification gaps) are in hand.

---

## Verification gaps

Google's documentation host and Cloudflare's docs site couldn't be fetched directly from the session
that drafted this. How each source was read instead:

- **Cloudflare pages:** read from the source of the published docs (the `production` branch of
  Cloudflare's public `cloudflare-docs` repository, 2026-10-14). That's the same text as the URLs
  cited.
- **Google pages, and Cloudflare's TLD policies page:** read **only through search-engine excerpts**.
  The Documenter's finalisation pass below re-read the pages that mattered.

**Finalisation pass, 2026-10-14 (Documenter).** Pages fetched directly this time:

1. **[GCP-RUN-MAP]: confirmed.** The page lists the same ten domain-mapping regions, and
   `northamerica-northeast1` is absent. It still says the feature is *Limited availability and
   Preview*, "not production-ready and … not supported at General Availability", and "not
   recommended for production services". **[GCP-RUN-LOC]** was not re-fetched; its claim is the
   same region list and rests on [GCP-RUN-MAP].
2. **[GCP-UPTIME]: confirmed.** Google's own page says the check "attempts to connect over HTTPS
   and validate the SSL certificate", that checks fail on an invalid certificate, and that
   `monitoring.googleapis.com/uptime_check/time_until_ssl_cert_expires` can drive an alerting
   policy. [GCP-UPTIME-CHARTS] stays a title-only excerpt and is no longer relied on for the metric.
3. **[GCP-CERTMGR]: confirmed**, with a limit: the page lists the regional external Application Load
   Balancer as supported and says Google-managed certificates are issued and renewed automatically,
   but gives **no validity period or renewal window** (see §3).
4. **[CF-LIMITS]: new source** for the proxied request-body limit (§2.2a).

**Still open, so §2.2b's price is not final:**

- **[GCP-LB-PRICE] / [GCP-NET-PRICE]:** the Montréal data-processing rate, and whether the regional
  external ALB has a separate proxy-instance charge. Google's pricing pages returned only a title
  and a truncation marker through the fetch tool (2026-10-14), so neither figure could be read.
  Someone needs to open the Cloud Load Balancing section of the live page in a browser, then restate
  the monthly figure. The $18.25/month floor is the forwarding-rule charge only.
- **[CF-TLD-POLICY]:** confirm the chosen TLD once Andy names the domain.

---

## Sources

| Key | URL | How read |
| - | - | - |
| CF-REG | https://developers.cloudflare.com/registrar/ | docs source |
| CF-FAQ | https://developers.cloudflare.com/registrar/faq/ | docs source |
| CF-XFER-IN | https://developers.cloudflare.com/registrar/get-started/transfer-domain-to-cloudflare/ | docs source |
| CF-XFER-OUT | https://developers.cloudflare.com/registrar/account-options/transfer-out-from-cloudflare/ | docs source |
| CF-TLD | https://developers.cloudflare.com/registrar/top-level-domains/ | docs source |
| CF-TLD-POLICY | https://www.cloudflare.com/tld-policies/ | search excerpt |
| CF-NS | https://developers.cloudflare.com/dns/nameservers/update-nameservers/ | docs source |
| CF-PAGES | https://developers.cloudflare.com/pages/configuration/custom-domains/ | docs source |
| CF-USSL | https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/ | docs source |
| CF-VALIDITY | https://developers.cloudflare.com/ssl/reference/certificate-validity-periods/ | docs source |
| CF-ORIGIN-CLOUD | https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/start/advanced-settings/custom-origin/ | docs source |
| CF-ORIGIN-RULES | https://developers.cloudflare.com/rules/origin-rules/ | docs source |
| CF-SNIPPETS | https://developers.cloudflare.com/rules/snippets/ | docs source |
| CF-WORKERS-FETCH | https://developers.cloudflare.com/workers/runtime-apis/fetch/ | docs source |
| CF-WORKERS-PRICING | https://developers.cloudflare.com/workers/platform/pricing/ | docs source |
| CF-LIMITS | https://developers.cloudflare.com/workers/platform/limits/ | read directly 2026-10-14 |
| GCP-RUN-LOC | https://docs.cloud.google.com/run/docs/locations | search excerpt |
| GCP-RUN-MAP | https://docs.cloud.google.com/run/docs/mapping-custom-domains | read directly 2026-10-14 |
| GCP-RUN-SEC | https://docs.cloud.google.com/run/docs/securing/security | search excerpt |
| GCP-RUN-HTTPS | https://docs.cloud.google.com/run/docs/triggering/https-request | search excerpt |
| GCP-LB-REGIONAL | https://docs.cloud.google.com/load-balancing/docs/https/setting-up-reg-ext-https-serverless | search excerpt |
| GCP-CERTMGR | https://docs.cloud.google.com/certificate-manager/docs/overview | read directly 2026-10-14 |
| GCP-LB-PRICE | https://cloud.google.com/load-balancing/pricing | search excerpt |
| GCP-LB-PRICE-ANN | https://cloud.google.com/load-balancing/pricing-announce | search excerpt |
| GCP-NET-PRICE | https://cloud.google.com/vpc/network-pricing | search excerpt |
| GCP-UPTIME | https://docs.cloud.google.com/monitoring/uptime-checks | read directly 2026-10-14 |
| GCP-UPTIME-CHARTS | https://docs.cloud.google.com/monitoring/charts/uptime-charts | search excerpt (page title only); not relied on |
