output "database_name" {
  value       = google_sql_database.this.name
  description = "The environment's database (ecofolk_qa)."
}

# A name, not a user: the user and its password are made out of band (LOCAL FOLLOW-UP L-SQL in main.tf).
output "user_name" {
  value       = "ecofolk${local.db_suffix}_app"
  description = "Name of the environment's own DB user (ecofolk_qa_app). Created out of band with its password, never here."
}

# #13: every name this module gives a resource, as <type>/<name>, for environments/qa's test that no
# name collides between dev and qa.
output "resource_names" {
  value       = ["google_sql_database/${google_sql_database.this.name}"]
  description = "Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test)."
}
