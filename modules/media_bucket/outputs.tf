output "bucket_name" {
  value       = google_storage_bucket.media.name
  description = "The media bucket's name (<project_id>-media)."
}

output "bucket_url" {
  value       = google_storage_bucket.media.url
  description = "The media bucket's gs:// URL."
}
