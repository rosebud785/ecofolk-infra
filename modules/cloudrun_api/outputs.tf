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

# Named env_vars, not env, since #13 (as the variable is).
output "env_vars" {
  value       = var.env_vars
  description = "The plain environment variables set on the container (non-secret), for environments' tests (#114)."
}

# ecofolk-infra#169: the secret refs mapped on the container (references only, never values), so an environment's test
# can assert the check-config job maps exactly the same set.
output "secret_env" {
  value       = var.secret_env
  description = "Env var name -> Secret Manager secret reference set on the container (references only), for environments' tests (#169)."
}

output "service_account" {
  value       = google_cloud_run_v2_service.api.template[0].service_account
  description = "The runtime service account the service runs as, for environments' tests (#169)."
}
