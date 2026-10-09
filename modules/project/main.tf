# main.tf — GCP project scaffolding (BUILD_PLAN.md §11.1).
#
# ⛔ NO `google` PROVIDER CREDENTIALS ARE CONFIGURED ANYWHERE IN THIS REPO,
# DELIBERATELY (ef#390). The GCP account does not exist yet — creating one
# starts the $300/90-day free-credit clock on ACCOUNT CREATION, not first
# use, so this skeleton is written and validated with no account, no
# credentials, and no `plan`/`apply` ever attempted against it. `terraform
# validate` only checks HCL syntax and each resource's argument schema
# against the provider's own (locally cached) schema — it never contacts
# GCP, so none of that requires credentials to exist.
#
# `for_each` over the enabled_apis list rather than one resource per API: the
# set is BUILD_PLAN.md §11.1's own list, kept as a single variable
# (variables.tf) so adding an API later is a one-line change here, not a new
# resource block.
resource "google_project_service" "apis" {
  for_each = toset(var.enabled_apis)

  project = var.project_id
  service = each.value

  # Never disable an API this module didn't know it needed to enable — a
  # future `destroy` of this module must not silently turn off something
  # another team enabled by hand for an unrelated reason.
  disable_on_destroy = false
}
