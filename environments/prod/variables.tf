# Prod root inputs (issue #12). None holds a secret or a credential, and none has a value in this repo:
# no tfvars are committed. CI only runs `validate` here, which needs no values.

# The runtime SA is created locally (L-RUN), not here; only its account id is named.
variable "api_service_account_id" {
  type        = string
  default     = "ecofolk-api"
  description = "Account id (the part before @) of the Cloud Run API's runtime service account in ecofolk-prod."
}

# Same name as dev's (#2): created locally (L1(a), ef#885) under exactly this id.
variable "ops_scheduler_service_account_id" {
  type        = string
  default     = "ops-scheduler"
  description = "Account id (the part before @) of the ops scheduler service account in ecofolk-prod; runs the nightly Cloud SQL export (#2)."
}

# The prod web app's bare hostname, for the auth config's authorized domains and the web-root uptime check
# (#5). The custom prod host is a go-live decision, not a guess; until it is set, the Hosting site's
# <site>.web.app is used (#143, as in dev).
variable "web_host" {
  type        = string
  default     = null
  description = "Bare hostname of the prod web app (no scheme, port or path). Null: the Hosting site's <site>.web.app."
}

# LOCAL FOLLOW-UP (L-RUN, go-live, #143): the migrate job's SA is created locally, never here. No default: its
# email is supplied at go-live, not guessed.
variable "migrate_service_account_email" {
  type        = string
  description = "Email of the migrate Cloud Run job's keyless service account in ecofolk-prod (ecofolk#1169). L-RUN go-live follow-up: supplied at go-live, created locally."
}

# LOCAL FOLLOW-UP (L-RUN, go-live, #143): the OIDC invoker SA for the idle-sit sweep and sync-usgs-water jobs is
# created locally with no roles, never here. No default.
variable "sweep_invoker_service_account_email" {
  type        = string
  description = "Email of the invoker service account the idle-sit sweep (#17) and sync-usgs-water (#98) jobs mint OIDC tokens for in ecofolk-prod. L-RUN go-live follow-up: supplied at go-live, created locally."
}

# Channel resource names only, never an address (#24, L-ALERT).
variable "alert_notification_channels" {
  type        = list(string)
  description = "Notification channel resource names (projects/<project>/notificationChannels/<n>) every prod alert notifies. Made by hand (L-ALERT)."
}

variable "db_connection_failure_log_filter" {
  type        = string
  description = "Cloud Logging filter matching one entry per failed database connection by the API. Supplied by L-ALERT."
}

variable "media_write_failure_log_filter" {
  type        = string
  description = "Cloud Logging filter matching one entry per failed media write by the API. Supplied by L-ALERT."
}
