# Test helper for qa_isolation.tftest.hcl (#13): reads the qa and dev roots' HCL (passed in as variables)
# and reports (1) whether the qa root declares a google_sql_database_instance, itself or through a module
# call whose source declares one, and (2) which module calls in each root are missing from that root's
# resource_names output, so the dev/qa collision check can't pass by leaving a module out.
terraform {
  required_version = ">= 1.5.0"
}

variable "qa_main_tf" {
  type        = string
  description = "Contents of environments/qa/main.tf."
}

variable "qa_root_tf" {
  type        = list(string)
  description = "Contents of each environments/qa/*.tf file."
}

variable "dev_main_tf" {
  type        = string
  description = "Contents of environments/dev/main.tf."
}

variable "module_sources" {
  type        = map(string)
  description = "Module directory name under modules/ => its *.tf contents, joined."
}

locals {
  instance_resource = "resource \"google_sql_database_instance\""

  # module "<name>" { source = "../../modules/<dir>" ... }
  call_pattern = "module \"([a-z0-9_]+)\" \\{\\s*source\\s*=\\s*\"\\.\\./\\.\\./modules/([a-z0-9_]+)\""
  qa_calls     = regexall(local.call_pattern, var.qa_main_tf)
  dev_calls    = regexall(local.call_pattern, var.dev_main_tf)
}

output "qa_calls" {
  value       = sort([for c in local.qa_calls : c[0]])
  description = "Module calls in the qa root."
}

output "dev_calls" {
  value       = sort([for c in local.dev_calls : c[0]])
  description = "Module calls in the dev root."
}

output "qa_root_declares_instance" {
  value       = anytrue([for f in var.qa_root_tf : strcontains(f, local.instance_resource)])
  description = "True if a qa root file declares a google_sql_database_instance itself."
}

output "qa_modules_with_instance" {
  value       = sort([for c in local.qa_calls : c[0] if strcontains(lookup(var.module_sources, c[1], ""), local.instance_resource)])
  description = "qa module calls whose source declares a google_sql_database_instance."
}

output "qa_unknown_sources" {
  value       = sort([for c in local.qa_calls : c[1] if !contains(keys(var.module_sources), c[1])])
  description = "qa module sources the helper couldn't read, so a hidden instance can't pass unseen."
}

output "qa_uncovered" {
  value       = sort([for c in local.qa_calls : c[0] if !strcontains(var.qa_main_tf, "module.${c[0]}.resource_names")])
  description = "qa module calls that the qa root's resource_names output leaves out."
}

output "dev_uncovered" {
  value       = sort([for c in local.dev_calls : c[0] if !strcontains(var.dev_main_tf, "module.${c[0]}.resource_names")])
  description = "dev module calls that the dev root's resource_names output leaves out."
}
