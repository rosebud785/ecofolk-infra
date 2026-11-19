output "name" {
  value       = google_cloud_run_v2_job.check_config.name
  description = "Cloud Run job name, for the deploy script's `gcloud run jobs update/execute` (ecofolk#1419)."
}

# #13: every name this module gives a resource, as <type>/<name>, for environments/qa's test that no
# name collides between dev and qa.
output "resource_names" {
  value       = ["google_cloud_run_v2_job/${google_cloud_run_v2_job.check_config.name}"]
  description = "Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test)."
}

output "env_vars" {
  value       = var.env_vars
  description = "The plain environment variables set on the container (non-secret), for environments' tests."
}

output "secret_env" {
  value       = var.secret_env
  description = "Env var name -> Secret Manager secret reference set on the container (references only), for environments' tests."
}

output "service_account" {
  value       = google_cloud_run_v2_job.check_config.template[0].template[0].service_account
  description = "The service account the job runs as, for environments' tests that it is the API's."
}
