output "secret_ids" {
  value       = { for name, s in google_secret_manager_secret.secret : name => s.id }
  description = "Map from secret name to its id (projects/<project>/secrets/<name>), for the Cloud Run secretKeyRef mapping (ecofolk-infra#66)."
}
