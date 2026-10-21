output "project_id" {
  value       = var.project_id
  description = "The GCP project id this module was instantiated for."
}

output "region" {
  value       = var.region
  description = "The (pinned) region this module was instantiated for. Always northamerica-northeast1 — see variables.tf."
}

# #13: every API this module enables (a project-wide singleton per API) and every name it gives a resource, as <type>/<name>, for environments/qa's test that no
# name collides between dev and qa.
output "resource_names" {
  value       = [for s in google_project_service.apis : "google_project_service/${s.service}"]
  description = "Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test)."
}
