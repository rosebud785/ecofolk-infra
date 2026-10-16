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
