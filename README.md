# ecofolk-infra

Terraform for the EcoFolk GCP environments (BUILD_PLAN §11.1). Public repo: nothing here may hold a
secret, and no pull-request path may obtain cloud credentials (`scripts/check-workflows.sh`).

```
environments/dev/    root module, project ecofolk-dev; applied keyless from main (.github/workflows/infra-apply.yml)
environments/prod/   root module, project ecofolk-prod; never applied by CI
modules/project/     reusable: enables the §11.1 APIs on one project
modules/network/     reusable: VPC, subnet, Private Service Access for Cloud SQL private IP (#1)
scripts/             check-region-pin.sh (ef#391), check-workflows.sh (E4) and their tests
policy/              conftest rules over the HCL (#7): Cloud Run / Cloud SQL / bucket limits, IAM boundary
```

**No GCP key exists anywhere.** `infra-apply.yml` (push to main only) exchanges the job's GitHub OIDC
token through Workload Identity Federation; GCP trusts it only for this repo's `refs/heads/main` and
the `gcp-dev` Environment. PRs run `fmt`, `validate`, `tflint`, `region-pin`, `workflow-guard` and
`policy` and nothing that can reach GCP.

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
- every `module` source is a local path (`./` or `../`), so no remote module hides resources from the rules.

A constrained argument must be a literal: `var.x` can't be checked without a plan, so the rule refuses it.
Everything outside `environments/prod/`, `modules/` included, gets the dev limits. Each rule has a passing and a failing fixture in `policy/tests/`.

## Region pin

Every resource runs in `northamerica-northeast1` (Montréal): `modules/project/variables.tf` validates
the `region` variable, and `scripts/check-region-pin.sh` greps the committed `*.tf`/`*.tfvars` for any
other region token or `global`. The app repo's own guard (`packages/scripts/src/lint-region-pin.ts`)
covers application code there.

## Running the checks locally

```bash
terraform fmt -check -recursive
for m in modules/*/; do [ -d "$m/tests" ] && terraform -chdir="$m" init -backend=false -input=false && terraform -chdir="$m" test; done
cd environments/dev && terraform init -backend=false -input=false && terraform validate
bash scripts/tests/test_check_region_pin.sh && bash scripts/check-region-pin.sh
bash scripts/tests/test_check_workflows.sh && bash scripts/check-workflows.sh
conftest verify --policy policy --data policy/data.json
bash scripts/tests/test_policy_files.sh
conftest test --parser hcl2 --combine --policy policy --data policy/data.json $(bash scripts/policy-files.sh)
```

History and rationale: ecofolk#827, #828, #883; design DESIGN-ecofolk-infra-guardrails-E4.
