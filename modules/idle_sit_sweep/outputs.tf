output "job_name" {
  value       = google_cloud_scheduler_job.sweep.name
  description = "Name of the idle-sit sweep Cloud Scheduler job."
}

output "audience" {
  value       = google_cloud_scheduler_job.sweep.http_target[0].oidc_token[0].audience
  description = "The OIDC audience the job's ID token carries (the endpoint URL); the API must expect exactly this."
}
