output "job_names" {
  value       = { for k, j in google_cloud_scheduler_job.this : k => j.name }
  description = "Names of the Cloud Scheduler jobs, keyed stop and start. Empty when enable_off_hours is false."
}
