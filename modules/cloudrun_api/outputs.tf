output "uri" {
  value       = google_cloud_run_v2_service.api.uri
  description = "The service's run.app URI. Not callable by the public until L-RUN adds the invoker binding."
}

output "name" {
  value       = google_cloud_run_v2_service.api.name
  description = "Cloud Run service name."
}

# #13: every name this module gives a resource, as <type>/<name>, for environments/qa's test that no
# name collides between dev and qa.
output "resource_names" {
  value       = ["google_cloud_run_v2_service/${google_cloud_run_v2_service.api.name}"]
  description = "Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test)."
}
