output "project_id" {
  value       = var.project_id
  description = "The GCP project id this module was instantiated for."
}

output "region" {
  value       = var.region
  description = "The (pinned) region this module was instantiated for. Always northamerica-northeast1 — see variables.tf."
}
