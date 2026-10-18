output "job_name" {
  value       = google_cloud_scheduler_job.sweep.name
  description = "Name of the idle-sit sweep Cloud Scheduler job, for the out-of-band header update."
}
