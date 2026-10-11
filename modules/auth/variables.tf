variable "project_id" {
  type        = string
  description = "GCP project id whose Firebase Auth / Identity Platform config this manages."
}

variable "web_host" {
  type        = string
  default     = null
  description = "Bare hostname of the environment's web app (no scheme, no path). Added to the default authorized_domains."

  validation {
    condition     = var.web_host == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.web_host))
    error_message = "web_host must be a bare lowercase hostname, e.g. app.example.com (no scheme, port or path)."
  }
}

# null means the spec default: ["localhost", var.web_host].
variable "authorized_domains" {
  type        = list(string)
  default     = null
  description = "Domains allowed for auth redirects and email action links. Default (null): localhost plus var.web_host."

  validation {
    condition     = alltrue([for d in var.authorized_domains == null ? [] : var.authorized_domains : can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", d))])
    error_message = "every authorized domain must be a bare lowercase hostname (no scheme, port or path)."
  }
}
