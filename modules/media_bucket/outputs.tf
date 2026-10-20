output "bucket_name" {
  value       = google_storage_bucket.media.name
  description = "The media bucket's name (<project_id>-media)."
}

output "bucket_url" {
  value       = google_storage_bucket.media.url
  description = "The media bucket's gs:// URL."
}

# #13: every name this module gives a resource, as <type>/<name>, for environments/qa's test that no
# name collides between dev and qa.
output "resource_names" {
  value       = ["google_storage_bucket/${google_storage_bucket.media.name}"]
  description = "Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test)."
}
