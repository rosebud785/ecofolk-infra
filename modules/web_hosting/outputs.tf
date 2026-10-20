# Built from site_id rather than read from the site's computed default_url, so it is known at plan time
# and can feed modules/auth's authorized_domains in the same plan. Firebase serves every site at
# https://<site_id>.web.app.
output "default_url" {
  value       = "https://${google_firebase_hosting_site.web.site_id}.web.app"
  description = "The site's default URL (https://<site>.web.app), for the auth authorized domains and the API's CORS allowlist."
}

output "default_host" {
  value       = "${google_firebase_hosting_site.web.site_id}.web.app"
  description = "Bare hostname of default_url (no scheme), the form modules/auth's web_host takes."
}

output "site_id" {
  value       = google_firebase_hosting_site.web.site_id
  description = "The Hosting site id, for `firebase deploy --only hosting:<site>` (ecofolk#408)."
}

# #13: every name this module gives a resource (Firebase is one per project, so its name is the project), as <type>/<name>, for environments/qa's test that no
# name collides between dev and qa.
output "resource_names" {
  value = [
    "google_firebase_project/${google_firebase_project.this.project}",
    "google_firebase_hosting_site/${google_firebase_hosting_site.web.site_id}",
  ]
  description = "Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test)."
}
