# modules/billing_killswitch — dev billing kill-switch

ecofolk-infra#15. A budget only sends alerts; it doesn't stop spend. This module is Google's standard
pattern for a real cap: the budget publishes to a Pub/Sub topic, and a Cloud Functions (2nd gen) Python
function unlinks billing from the project once the budget's actual spend reaches the threshold.

**Dev only. Never prod.** Unlinking prod's billing takes the beta down. `environments/prod` never calls this
module. The function acts only on a project in `project_allowlist` (default `["ecofolk-dev"]`), and C7
(`policy/billing_killswitch.rego`) refuses any allowlist that holds a `*-prod` id.

## What it manages

- topic `ecofolk-dev-killswitch` (`topic_name`), with message storage in Montréal only;
- function `ecofolk-dev-killswitch` (`function_name`) in `northamerica-northeast1`, Python, triggered by
  the topic's messages, 0–1 instances, internal ingress only, running as `ecofolk-killswitch@<project>`
  (`service_account_id`; the SA is created locally, not here);
- bucket `<project>-killswitch-src` (private, Montréal) for the function's source zip;
- the Cloud Functions, Eventarc, Pub/Sub and Cloud Billing APIs.

The names are the Architect's defaults on #15. They match the local ef#885 paste, so don't rename them.

## What the function does

On each budget message it unlinks billing (`cloudbilling.projects.updateBillingInfo` with an empty
billing account) only when **all** of these hold:

1. `budgetDisplayName` is `budget_display_name` (default `ecofolk-dev-killswitch`); every other budget's
   message is ignored, so `ecofolk-all` can never trip it;
2. the project is on `project_allowlist`;
3. `costAmount >= budgetAmount × unlink_threshold` (default `1.0`, i.e. 100% of actual spend). A
   forecasted-spend alert never unlinks: only the actual `costAmount` counts.

Every unlink logs the triggering `costAmount` and the budget name. Unit tests (mocked billing client):

```bash
python3 -m unittest discover -s modules/billing_killswitch/tests -p 'test_*.py'
```

## The budget it watches (created locally, not here)

`ecofolk-dev-killswitch`: a **dedicated** budget scoped to project `ecofolk-dev`, $25/month, with alert
rules at 50%, 90% and 100% of current spend and 100% of forecasted spend (Andy, 2026-10-09, provisional).
It isn't `ecofolk-all`, so spend in another project can't trip the unlink. `ecofolk-all` stays
email-only and isn't wired to this topic.

**The budget counts gross cost, with credits excluded** (`--credit-types-treatment=exclude-all-credits`).
With credits included, the $300 trial credit nets each month's spend to about $0, so the switch could never
fire while the credit lasts.

## What unlinking does

Unlinking billing stops every billed service in `ecofolk-dev`. That includes the QA namespace (#13),
which goes down with it. That's accepted. Relinking billing is a manual, local step.

## Not here (LOCAL FOLLOW-UP, ecofolk#885 L1(b))

- creating the budget and pointing it at this topic;
- creating the runtime SA `ecofolk-killswitch`, and tf-apply's actAs on it;
- `roles/billing.projectManager` for that SA on `ecofolk-dev` only;
- the trigger's grants: `roles/eventarc.eventReceiver` for the SA on `ecofolk-dev`, and `roles/run.invoker`
  for it on this function's service only.

This public repo writes no IAM.
