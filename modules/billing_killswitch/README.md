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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| archive | ~> 2.0 |
| google | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| archive | ~> 2.0 |
| google | ~> 5.0 |

## Resources

| Name | Type |
|------|------|
| [google_cloudfunctions2_function.killswitch](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloudfunctions2_function) | resource |
| [google_project_service.apis](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_pubsub_topic.budget](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic) | resource |
| [google_storage_bucket.source](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_object.source](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_object) | resource |
| [archive_file.source](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| budget_display_name | The only budget whose messages the function acts on; every other budget (ecofolk-all included) is ignored. | `string` | `"ecofolk-dev-killswitch"` | no |
| function_name | Name of the Cloud Functions (2nd gen) function (and its Cloud Run service). | `string` | `"ecofolk-dev-killswitch"` | no |
| project_allowlist | Project ids the function may unlink billing from. It does nothing for any other project. Never a *-prod id. | `list(string)` | ```[ "ecofolk-dev" ]``` | no |
| project_id | GCP project id that hosts the topic and function, and whose billing the function unlinks. No default: every caller states its own project. | `string` | n/a | yes |
| region | Region of the function, its trigger, the topic's message storage and the source bucket. Must always be northamerica-northeast1 (Montréal), ef#391. | `string` | `"northamerica-northeast1"` | no |
| service_account_id | Account id (the part before @) of the function's runtime SA, also used by its trigger. Created locally (ef#885), not here. | `string` | `"ecofolk-killswitch"` | no |
| topic_name | Pub/Sub topic the budget publishes to. The local budget script (ef#885) points the budget at this name. | `string` | `"ecofolk-dev-killswitch"` | no |
| unlink_threshold | The function unlinks when costAmount >= budgetAmount x this. 1.0 = 100% of the budget's actual (gross) spend. | `number` | `1` | no |

## Outputs

| Name | Description |
|------|-------------|
| function_name | The kill-switch function's name, for the local run.invoker grant on its service (ef#885). |
| service_account_email | The runtime and trigger SA the function expects (created locally, ef#885). |
| topic_id | The budget topic (projects/<project>/topics/<name>), for the local budget wiring (ef#885). |
<!-- END_TF_DOCS -->
