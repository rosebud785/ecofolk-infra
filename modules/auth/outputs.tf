output "auth_domain" {
  value       = "${var.project_id}.firebaseapp.com"
  description = "The project's Firebase auth domain (<project>.firebaseapp.com), for the web build's Firebase config."
}

output "authorized_domains" {
  value       = google_identity_platform_config.auth.authorized_domains
  description = "The authorized domains set on the config."
}
