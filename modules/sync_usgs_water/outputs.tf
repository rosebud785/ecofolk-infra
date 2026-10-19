output "job_name" {
  value       = google_cloud_scheduler_job.sync.name
  description = "Name of the sync-usgs-water Cloud Scheduler job."
}

output "audience" {
  value       = google_cloud_scheduler_job.sync.http_target[0].oidc_token[0].audience
  description = "The OIDC audience the job's ID token carries (the endpoint URL); the API must expect exactly this."
}

output "scheduler_jobs" {
  value = [{
    name      = google_cloud_scheduler_job.sync.name
    schedule  = google_cloud_scheduler_job.sync.schedule
    time_zone = google_cloud_scheduler_job.sync.time_zone
  }]
  description = "This module's Cloud Scheduler jobs (name, schedule, time_zone), for environments/dev's stop-window test (#99)."
}
