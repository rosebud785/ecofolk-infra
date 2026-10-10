output "repository_id" {
  value       = google_artifact_registry_repository.docker.repository_id
  description = "The Artifact Registry repository id."
}

output "location" {
  value       = google_artifact_registry_repository.docker.location
  description = "The repository's location. Always northamerica-northeast1 — see variables.tf."
}

output "docker_host" {
  value       = "${google_artifact_registry_repository.docker.location}-docker.pkg.dev"
  description = "Docker registry host for this repository (<location>-docker.pkg.dev)."
}
