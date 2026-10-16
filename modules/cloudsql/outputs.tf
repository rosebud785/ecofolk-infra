output "connection_name" {
  value       = google_sql_database_instance.postgres.connection_name
  description = "Instance connection name (<project>:<region>:<instance>), for the Cloud SQL connector."
}

output "private_ip_address" {
  value       = google_sql_database_instance.postgres.private_ip_address
  description = "The instance's private IP inside the PSA range. There is no public IP."
}

output "database_name" {
  value       = google_sql_database.ecofolk.name
  description = "Name of the application database."
}

output "instance_service_account_email" {
  value       = google_sql_database_instance.postgres.service_account_email_address
  description = "The instance's own service account. The export writes as it, so LOCAL FOLLOW-UP L1(a) grants it write on the export bucket."
}

output "export_bucket_name" {
  value       = google_storage_bucket.sql_exports.name
  description = "Bucket the nightly export lands in (<project_id>-sql-exports)."
}

output "export_job_name" {
  value       = google_cloud_scheduler_job.sql_export.name
  description = "Name of the Cloud Scheduler job that runs the nightly export."
}
