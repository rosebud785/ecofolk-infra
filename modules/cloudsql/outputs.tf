output "connection_name" {
  value       = google_sql_database_instance.postgres.connection_name
  description = "Instance connection name (<project>:<region>:<instance>), for the Cloud SQL connector."
}

output "instance_name" {
  value       = google_sql_database_instance.postgres.name
  description = "The instance's name, for modules/sql_off_hours' stop and start jobs (#14)."
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

output "scheduler_jobs" {
  value = [{
    name      = google_cloud_scheduler_job.sql_export.name
    schedule  = google_cloud_scheduler_job.sql_export.schedule
    time_zone = google_cloud_scheduler_job.sql_export.time_zone
  }]
  description = "This module's Cloud Scheduler jobs (name, schedule, time_zone), for environments/dev's stop-window test (#99)."
}

# #13: every name this module gives a resource, as <type>/<name>, for environments/qa's test that no
# name collides between dev and qa.
output "resource_names" {
  value = concat([
    "google_sql_database_instance/${google_sql_database_instance.postgres.name}",
    "google_sql_database/${google_sql_database.ecofolk.name}",
    "google_storage_bucket/${google_storage_bucket.sql_exports.name}",
    "google_cloud_scheduler_job/${google_cloud_scheduler_job.sql_export.name}",
  ], [for u in google_sql_user.migrate : "google_sql_user/${u.name}"])
  description = "Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test)."
}

# #144: the planned protections and windows, so a root's plan test (environments/prod/tests) can assert the
# values the root actually gets (a test can read module outputs, not resources inside modules).
output "protections" {
  value = {
    deletion_protection         = google_sql_database_instance.postgres.deletion_protection
    deletion_protection_enabled = google_sql_database_instance.postgres.settings[0].deletion_protection_enabled
    backup_enabled              = google_sql_database_instance.postgres.settings[0].backup_configuration[0].enabled
    pitr_enabled                = google_sql_database_instance.postgres.settings[0].backup_configuration[0].point_in_time_recovery_enabled
    transaction_log_days        = google_sql_database_instance.postgres.settings[0].backup_configuration[0].transaction_log_retention_days
    backup_start_time           = google_sql_database_instance.postgres.settings[0].backup_configuration[0].start_time
    maintenance_day             = google_sql_database_instance.postgres.settings[0].maintenance_window[0].day
    maintenance_hour            = google_sql_database_instance.postgres.settings[0].maintenance_window[0].hour
    region                      = google_sql_database_instance.postgres.region
    export_job_schedule         = google_cloud_scheduler_job.sql_export.schedule
  }
  description = "Deletion protection, backup/PITR and the C2 ops windows as planned, for environments/prod's tests (#144)."
}
