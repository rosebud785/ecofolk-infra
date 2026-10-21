output "job_name" {
  value       = google_cloud_scheduler_job.sweep.name
  description = "Name of the idle-sit sweep Cloud Scheduler job."
}

output "audience" {
  value       = google_cloud_scheduler_job.sweep.http_target[0].oidc_token[0].audience
  description = "The OIDC audience the job's ID token carries (the endpoint URL); the API must expect exactly this."
}

output "uri" {
  value       = google_cloud_scheduler_job.sweep.http_target[0].uri
  description = "The URL the job POSTs to; equals audience (#114's test asserts it)."
}

output "scheduler_jobs" {
  value = [{
    name      = google_cloud_scheduler_job.sweep.name
    schedule  = google_cloud_scheduler_job.sweep.schedule
    time_zone = google_cloud_scheduler_job.sweep.time_zone
  }]
  description = "This module's Cloud Scheduler jobs (name, schedule, time_zone), for environments/dev's stop-window test (#99)."
}

# #13: every name this module gives a resource, as <type>/<name>, for environments/qa's test that no
# name collides between dev and qa.
output "resource_names" {
  value       = ["google_cloud_scheduler_job/${google_cloud_scheduler_job.sweep.name}"]
  description = "Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test)."
}
