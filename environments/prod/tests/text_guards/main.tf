# Test helper for prod.tftest.hcl (#144): facts about environments/prod's source that a plan cannot show, because
# a plan only has values. The test passes the file contents in as variables.
terraform {
  required_version = ">= 1.5.0"
}

variable "root_tf" {
  type        = list(string)
  description = "Contents of each environments/prod/*.tf file."
}

locals {
  all = join("\n", var.root_tf)
  # Comments may say "sql_off_hours"; only a module block counts.
  module_blocks = [for m in regexall("(?m)^module \"([a-z0-9_]+)\"", local.all) : m[0]]
  # Any GCP region literal (a continent prefix, a name and a number).
  region_literals = distinct(regexall("(?:us|europe|asia|northamerica|southamerica|australia|me|africa)-[a-z]+[0-9]+", replace(local.all, "/(?m)^\\s*#.*$/", "")))
}

output "module_blocks" {
  value = local.module_blocks
}

output "region_literals" {
  value = local.region_literals
}

# A region set on a provider block would bypass module.project's pin.
output "provider_sets_region" {
  value = can(regex("(?s)provider \"google[a-z-]*\" \\{[^}]*region", local.all))
}
