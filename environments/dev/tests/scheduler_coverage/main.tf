# Test helper for scheduler_window.tftest.hcl (#99): finds the module calls in environments/dev/main.tf
# whose source declares a google_cloud_scheduler_job, and which of them the root's scheduler_jobs output
# leaves out. The test passes the file contents in as variables.
terraform {
  required_version = ">= 1.5.0"
}

variable "main_tf" {
  type        = string
  description = "Contents of environments/dev/main.tf."
}

variable "module_sources" {
  type        = map(string)
  description = "Module directory name under modules/ => its *.tf contents, joined."
}

variable "root_tf" {
  type        = list(string)
  description = "Contents of each environments/dev/*.tf file."
}

locals {
  scheduler_resource = "resource \"google_cloud_scheduler_job\""

  # module "<name>" { source = "../../modules/<dir>" ... }
  calls = regexall("module \"([a-z0-9_]+)\" \\{\\s*source\\s*=\\s*\"\\.\\./\\.\\./modules/([a-z0-9_]+)\"", var.main_tf)

  with_jobs = sort([for c in local.calls : c[0] if strcontains(lookup(var.module_sources, c[1], ""), local.scheduler_resource)])
}

output "modules_with_jobs" {
  value       = local.with_jobs
  description = "Module calls whose source declares a google_cloud_scheduler_job."
}

output "uncovered" {
  value       = [for m in local.with_jobs : m if !strcontains(var.main_tf, "module.${m}.scheduler_jobs")]
  description = "Of those, the ones main.tf doesn't read scheduler_jobs from."
}

output "root_declares_jobs" {
  value       = anytrue([for f in var.root_tf : strcontains(f, local.scheduler_resource)])
  description = "True if environments/dev declares a google_cloud_scheduler_job itself."
}
