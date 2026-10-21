variable "project_id" {
  type        = string
  description = "GCP project id that owns the instance (ecofolk-dev for qa). No default: every caller states its own project."
}

# The existing instance's name, e.g. data.google_sql_database_instance.<x>.name. This module never creates
# an instance (#13).
variable "instance_name" {
  type        = string
  description = "Name of the existing Cloud SQL instance to create the database on (dev's, for qa)."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,96}[a-z0-9])?$", var.instance_name))
    error_message = "instance_name must start with a lowercase letter and contain only lowercase letters, digits and hyphens (max 98 chars)."
  }
}

# #13: the environment this database belongs to; it names the database and the user. Only qa: dev's and
# prod's databases are modules/cloudsql's "ecofolk", and a dev or prod call here would collide with it.
variable "env" {
  type        = string
  description = "Environment. Must be \"qa\" (#13): dev and prod get their database from modules/cloudsql. Names the database ecofolk_qa and the user ecofolk_qa_app."

  validation {
    condition     = var.env == "qa"
    error_message = "env must be \"qa\": dev and prod get their database from modules/cloudsql (#13)."
  }
}
