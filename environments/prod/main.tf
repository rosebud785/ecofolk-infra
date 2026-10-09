# prod environment root module — BUILD_PLAN.md §11.1's ecofolk-prod project.
# See ../dev/main.tf for why there's no provider-credential or backend block
# yet, and why `region` is deliberately never set here either.
module "project" {
  source     = "../../modules/project"
  project_id = "ecofolk-prod"
}
