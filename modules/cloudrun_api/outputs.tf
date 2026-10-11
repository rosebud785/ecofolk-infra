output "uri" {
  value       = google_cloud_run_v2_service.api.uri
  description = "The service's run.app URI. Not callable by the public until L-RUN adds the invoker binding."
}

output "name" {
  value       = google_cloud_run_v2_service.api.name
  description = "Cloud Run service name."
}
