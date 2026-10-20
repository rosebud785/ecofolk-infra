output "secret_ids" {
  value       = { for name, s in google_secret_manager_secret.secret : name => s.id }
  description = "Map from secret name to its id (projects/<project>/secrets/<name>), for the Cloud Run secretKeyRef mapping (ecofolk-infra#66)."
}

# #13: every name this module gives a resource, as <type>/<name>, for environments/qa's test that no
# name collides between dev and qa.
output "resource_names" {
  value       = [for s in google_secret_manager_secret.secret : "google_secret_manager_secret/${s.secret_id}"]
  description = "Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test)."
}
