# ecofolk-infra

Terraform for the EcoFolk GCP environments (BUILD_PLAN §11.1). Public repo: nothing here may hold a
secret, and no pull-request path may obtain cloud credentials (`scripts/check-workflows.sh`).

```
environments/dev/    root module, project ecofolk-dev; applied keyless from main (.github/workflows/infra-apply.yml)
environments/prod/   root module, project ecofolk-prod; never applied by CI
modules/project/     reusable: enables the §11.1 APIs on one project
modules/artifact_registry/  reusable: region-pinned Docker repo with cleanup policies (#4)
modules/network/     reusable: VPC, subnet, Private Service Access for Cloud SQL private IP (#1)
modules/cloudsql/    reusable: Cloud SQL Postgres 16, private IP only, backups on, IAM auth flag (#18)
modules/cloudrun_api/ reusable: the API on Cloud Run v2, scale-to-zero, Direct VPC egress (#19)
modules/auth/        reusable: Firebase Auth config, email + password on, no IdP secrets (#20)
modules/media_bucket/ reusable: private GCS media bucket, Montréal, abort-multipart lifecycle only (#21)
modules/monitoring/  reusable: alerts on API 5xx rate, DB connection and media write failures; channels by ID only (#24); HTTPS uptime checks on API /health and web root (#5);
                     one dashboard, JSON in dashboards/ecofolk.json (#6)
modules/web_hosting/ reusable: Firebase Hosting site for the web build, <project>-web.web.app (#22)
modules/secrets/     reusable: Secret Manager secret containers (no versions), one replica in Montréal (#32)
modules/sql_off_hours/ dev only: Cloud Scheduler stops dev Cloud SQL at 22:15 CT and starts it at 04:45 CT (#14)
modules/billing_killswitch/ dev only: budget topic + function that unlinks ecofolk-dev's billing at 100% (#15)
scripts/             check-region-pin.sh (ef#391), check-workflows.sh (E4), test_secret_scan.sh (#33),
                     restore-from-export.sh (#3, run on-site only) and tests
.gitleaks.toml       secret-scan rules (#33); allowlist only via .gitleaksignore
.github/dependabot.yml weekly Dependabot PRs: terraform per env/module dir, plus github-actions (#10)
CONTRIBUTING.md      copy-in checklist for anything coming from a private repo
policy/              conftest rules over the HCL (#7): Cloud Run / Cloud SQL / bucket limits, IAM boundary
```

**No GCP key exists anywhere.** `infra-apply.yml` (push to main only) exchanges the job's GitHub OIDC
token through Workload Identity Federation; GCP trusts it only for this repo's `refs/heads/main` and
the `gcp-dev` Environment. PRs run `fmt`, `validate`, `tf-test`, `dashboard-json`, `tflint`, `region-pin`, `restore-script`, `workflow-guard`,
`secret-scan` and `policy` and nothing that can reach GCP.

## Dev billing kill-switch (#15)

A budget only alerts. `modules/billing_killswitch` (called from `environments/dev` only, never prod) is the
cap: budget `ecofolk-dev-killswitch` publishes to topic `ecofolk-dev-killswitch`, and a function unlinks
billing from `ecofolk-dev` once actual spend reaches 100% of the $25/month budget. It ignores every other
budget's messages and every project not on its allowlist (default `["ecofolk-dev"]`).

- **The budget counts gross cost, with credits excluded.** Otherwise the $300 trial credit nets each
  month to about $0, and the switch could never fire while the credit lasts. The budget is created locally
  (ecofolk#885), with `--credit-types-treatment=exclude-all-credits`.
- **Unlinking `ecofolk-dev` also takes the QA namespace (#13) down.** That's accepted.

Details: [modules/billing_killswitch/README.md](modules/billing_killswitch/README.md).

## Policy (cost and safety guards)

Budget is not a cap, so PR CI refuses the expensive or unsafe config in the HCL itself
(`policy/*.rego`, run by conftest on every tracked `*.tf` in the repo, listed by `scripts/policy-files.sh`;
a tracked `*.tf.json` fails the job, because the HCL parser can't read it):

- Cloud Run: only `google_cloud_run_v2_service` and `google_cloud_run_v2_job`; on services,
  `min_instance_count` 0, `max_instance_count` set and at most 3 (5 under `environments/prod/`), no
  `manual_instance_count`, and `scaling_mode` (if set) is `"AUTOMATIC"`;
- Cloud SQL: `tier` on the allowlist in `policy/data.json`, no `REGIONAL` outside prod, prod has
  `deletion_protection = true`;
- buckets: `public_access_prevention = "enforced"` and `uniform_bucket_level_access = true`;
- no `google_service_account_key` anywhere, and no `*_iam_*` resource outside a `local-only/` path;
- Secret Manager: no `google_secret_manager_secret_version` (a secret's value) and no
  `google_secret_manager_secret_iam_*` outside a `local-only/` path; secrets here are empty containers (#32);
- billing kill-switch: every `project_allowlist` (variable default or module argument) is a literal list
  with no `*-prod` id (#15);
- every `module` source is a local path (`./` or `../`) that resolves to a directory with tracked `*.tf`,
  so no remote or unresolvable module hides resources from the rules.

A constrained argument must be a literal: `var.x` can't be checked without a plan, so the rule refuses it.
One exception (#39, `policy/module_vars.rego`): a Cloud SQL `tier` or Cloud Run `max_instance_count`
written as exactly `var.X` in a file directly under `modules/<m>/` is accepted when `variable "X"` has a
literal default that passes the dev limits **and** every `module` block calling `modules/<m>` omits X or
passes a literal that passes under that call site's limits (prod limits under `environments/prod/`).
Everything outside `environments/prod/`, `modules/` included, gets the dev limits. Each rule has a passing and a failing fixture in `policy/tests/`.

## Region pin

Every resource runs in `northamerica-northeast1` (Montréal): `modules/project/variables.tf` validates
the `region` variable, and `scripts/check-region-pin.sh` greps the committed `*.tf`/`*.tfvars` for any
other region token or `global`, in any case (#26: GCS reports `NORTHAMERICA-NORTHEAST1`, and an
upper-case `US-CENTRAL1` is caught like lower case). The app repo's own guard (`packages/scripts/src/lint-region-pin.ts`)
covers application code there.

## Module tests (every module PR adds its own)

A PR can't run a real `plan` (no credentials), so each module proves itself with `terraform test`
against `mock_provider "google"`: no credentials, no GCP calls (#8). The rule:

- **every PR that adds a module adds `modules/<name>/tests/*.tftest.hcl` in the same PR**, and every
  PR that changes a module updates its tests to cover the change;
- the tests use `mock_provider "google" {}` and `command = plan` (or `apply`, which is mocked too),
  and assert the region pin, the cost/safety-relevant arguments, the outputs, and that each
  variable `validation` refuses a bad value (`expect_failures`);
- PR CI's `tf-test` job runs `terraform test` in every `modules/*` directory and **fails a module that
  has no `tests/*.tftest.hcl`**, so a module without tests can't merge green.

`terraform test` needs Terraform 1.7 or later (`mock_provider`).

## Running the checks locally

```bash
terraform fmt -check -recursive
for m in modules/*/; do [ -d "$m/tests" ] && terraform -chdir="$m" init -backend=false -input=false && terraform -chdir="$m" test; done
cd environments/dev && terraform init -backend=false -input=false && terraform validate
bash scripts/tests/test_check_region_pin.sh && bash scripts/check-region-pin.sh
bash scripts/tests/test_check_workflows.sh && bash scripts/check-workflows.sh
bash scripts/tests/test_restore_from_export.sh
bash scripts/tests/test_secret_scan.sh && gitleaks git --log-opts="HEAD" --config .gitleaks.toml --redact --exit-code 1 .
for f in $(git ls-files 'modules/*/dashboards/*.json'); do jq empty "$f"; done
conftest verify --policy policy --data policy/data.json
python3 -m unittest discover -s modules/billing_killswitch/tests -p 'test_*.py'
bash scripts/tests/test_policy_files.sh
conftest test --parser hcl2 --combine --policy policy --data policy/data.json $(bash scripts/policy-files.sh)
```

History and rationale: ecofolk#827, #828, #883; design DESIGN-ecofolk-infra-guardrails-E4.
