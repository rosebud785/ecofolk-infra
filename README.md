# ecofolk-infra

Terraform for the EcoFolk GCP environments (BUILD_PLAN §11.1). Public repo: nothing here may hold a
secret, and no pull-request path may obtain cloud credentials (`scripts/check-workflows.sh`).

```
environments/dev/    root module, project ecofolk-dev; applied keyless from main (.github/workflows/infra-apply.yml)
environments/prod/   root module, project ecofolk-prod; never applied by CI
modules/project/     reusable: enables the §11.1 APIs on one project
modules/network/     reusable: VPC, subnet, Private Service Access for Cloud SQL private IP (#1)
scripts/             check-region-pin.sh (ef#391), check-workflows.sh (E4) and their tests
```

**No GCP key exists anywhere.** `infra-apply.yml` (push to main only) exchanges the job's GitHub OIDC
token through Workload Identity Federation; GCP trusts it only for this repo's `refs/heads/main` and
the `gcp-dev` Environment. PRs run `fmt`, `validate`, `tflint`, `region-pin` and `workflow-guard`
and nothing that can reach GCP.

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
```

History and rationale: ecofolk#827, #828, #883; design DESIGN-ecofolk-infra-guardrails-E4.
