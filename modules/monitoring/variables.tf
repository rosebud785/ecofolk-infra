variable "project_id" {
  type        = string
  description = "GCP project id the alert policies and log-based metrics live in. No default: every caller states its own project."
}

# The Cloud Run service the 5xx policy watches: modules/cloudrun_api's `name` (pass module.cloudrun_api.name).
variable "api_service_name" {
  type        = string
  default     = "ecofolk-api"
  description = "Name of the API's Cloud Run service, for the 5xx policy's filter."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,47}[a-z0-9])?$", var.api_service_name))
    error_message = "api_service_name must be a Cloud Run service name (lowercase letters, digits and hyphens, max 49 chars)."
  }
}

# Issue #24 amendment: the channels are made by hand (email, owner's ruling) and only referenced here by
# ID. No default and not nullable, so an unset value fails the apply instead of shipping alerts that go
# nowhere. In CI the dev root is fed from repo variable ALERT_CHANNEL_IDS (TF_VAR_alert_notification_channels).
variable "notification_channels" {
  type        = list(string)
  nullable    = false
  description = "Notification channel resource names (projects/<project>/notificationChannels/<n>) every policy notifies. IDs only: never an address."

  validation {
    condition     = length(var.notification_channels) > 0
    error_message = "notification_channels must name at least one channel: an alert with no channel is no alert (#24)."
  }

  validation {
    condition = alltrue([
      for c in var.notification_channels : can(regex("^projects/[^/]+/notificationChannels/[0-9]+$", c))
    ])
    error_message = "each notification_channels entry must be a channel resource name, projects/<project>/notificationChannels/<n>."
  }
}

# Issue #24 spec item 4: the app's log line shapes live in the private repo, so the two log filters are
# inputs with no default. The apply fails until L-ALERT supplies them, rather than shipping a filter that
# matches nothing.
variable "db_connection_failure_log_filter" {
  type        = string
  nullable    = false
  description = "Cloud Logging filter matching one log entry per failed database connection attempt by the API. Supplied by L-ALERT."

  validation {
    condition     = trimspace(var.db_connection_failure_log_filter) != ""
    error_message = "db_connection_failure_log_filter must be a non-empty Cloud Logging filter (L-ALERT supplies it)."
  }
}

variable "media_write_failure_log_filter" {
  type        = string
  nullable    = false
  description = "Cloud Logging filter matching one log entry per failed media upload/write by the API. Supplied by L-ALERT."

  validation {
    condition     = trimspace(var.media_write_failure_log_filter) != ""
    error_message = "media_write_failure_log_filter must be a non-empty Cloud Logging filter (L-ALERT supplies it)."
  }
}

# Issue #5: the uptime checks' hosts are inputs. Bare hostnames only (no scheme, port or path): the
# check adds https:// and the path itself. No default: the API's Cloud Run hostname isn't knowable here,
# and a guessed host would probe the wrong thing.
variable "api_host" {
  type        = string
  nullable    = false
  description = "Hostname of the EcoFolk API (e.g. its Cloud Run run.app host), probed at https://<api_host>/health."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.api_host))
    error_message = "api_host must be a bare lowercase hostname: no scheme, port or path."
  }
}

variable "web_host" {
  type        = string
  nullable    = false
  description = "Hostname of the EcoFolk web build (modules/web_hosting: <project>-web.web.app), probed at https://<web_host>/."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.web_host))
    error_message = "web_host must be a bare lowercase hostname: no scheme, port or path."
  }
}

# Issue #6: the Cloud SQL instance the dashboard's database tiles watch (filtered on database_id
# "<project_id>:<instance>"); #109's stale-export alert names it in its documentation. Default is
# modules/cloudsql's own instance_name default.
variable "sql_instance_name" {
  type        = string
  default     = "ecofolk-pg"
  description = "Name of the Cloud SQL instance the dashboard's database tiles watch and the stale-export alert names (modules/cloudsql's instance_name)."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,96}[a-z0-9])?$", var.sql_instance_name))
    error_message = "sql_instance_name must be a Cloud SQL instance name (lowercase letters, digits and hyphens, max 98 chars)."
  }
}

# Issue #109 (Architect ruling on #111): the stale-export alert counts successful runs of this one Cloud
# Scheduler job. No default: the caller passes modules/cloudsql's export_job_name output, so the id is never
# a second copy that can drift from the job's real name.
variable "sql_export_job_name" {
  type        = string
  nullable    = false
  description = "Id of the nightly export's Cloud Scheduler job, for the stale-export alert (pass module.cloudsql.export_job_name)."

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,500}$", var.sql_export_job_name))
    error_message = "sql_export_job_name must be a Cloud Scheduler job id (letters, digits, hyphens and underscores, max 500 chars), not a full resource path."
  }
}

# Issue #6: the threshold line on the connections tile. Cloud SQL sets Postgres max_connections from the
# tier; 25 is db-f1-micro's, modules/cloudsql's default tier. Change both together.
variable "db_max_connections" {
  type        = number
  default     = 25
  description = "The Cloud SQL tier's max_connections, drawn as the connections tile's threshold. 25 = db-f1-micro."

  validation {
    condition     = var.db_max_connections > 0 && floor(var.db_max_connections) == var.db_max_connections
    error_message = "db_max_connections must be a positive whole number."
  }
}
