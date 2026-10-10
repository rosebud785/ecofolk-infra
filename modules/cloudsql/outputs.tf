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
