output "job_names" {
  value       = { for k, j in google_cloud_scheduler_job.this : k => j.name }
  description = "Names of the Cloud Scheduler jobs, keyed stop and start. Empty when enable_off_hours is false."
}

output "scheduler_jobs" {
  value = [for j in google_cloud_scheduler_job.this : {
    name      = j.name
    schedule  = j.schedule
    time_zone = j.time_zone
  }]
  description = "This module's Cloud Scheduler jobs (name, schedule, time_zone), for environments/dev's stop-window test (#99). Empty when enable_off_hours is false."
}
