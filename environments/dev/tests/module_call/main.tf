# Test helper for artifact_registry.tftest.hcl (#119): reads one module call out of environments/dev/main.tf
# and returns its source and the sorted names of the arguments it sets. The test passes the file contents
# in as a variable. The block is everything from `module "<name>" {` to the first line that is just `}`.
terraform {
  required_version = ">= 1.5.0"
}

variable "main_tf" {
  type        = string
  description = "Contents of environments/dev/main.tf."
}

variable "name" {
  type        = string
  description = "Name of the module call to read."
}

locals {
  blocks = regexall("(?ms)^module \"${var.name}\" \\{\\n(.*?)^\\}$", var.main_tf)
  body   = length(local.blocks) == 1 ? local.blocks[0][0] : ""
}

output "source" {
  value       = one([for m in regexall("(?m)^\\s*source\\s*=\\s*\"([^\"]*)\"", local.body) : m[0]])
  description = "The call's source, or null if the call is missing or has none."
}

output "arguments" {
  value       = sort(distinct([for m in regexall("(?m)^\\s*([a-z_]+)\\s*=", local.body) : m[0]]))
  description = "Sorted names of the top-level arguments the call sets (an empty list if the call is missing)."
}
