output "auth_domain" {
  value       = "${var.project_id}.firebaseapp.com"
  description = "The project's Firebase auth domain (<project>.firebaseapp.com), for the web build's Firebase config."
}

output "authorized_domains" {
  value       = google_identity_platform_config.auth.authorized_domains
  description = "The authorized domains set on the config."
}

# #13: the config is one per project, so its name is the project. Listed, as <type>/<name>, for environments/qa's test that no
# name collides between dev and qa.
output "resource_names" {
  value       = ["google_identity_platform_config/${google_identity_platform_config.auth.project}"]
  description = "Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test)."
}
