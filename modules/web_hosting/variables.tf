variable "project_id" {
  type        = string
  description = "GCP project id to add Firebase to and host the web build in. The site id is <project_id>-web."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a GCP project id: 6-30 lowercase letters, digits or hyphens, starting with a letter."
  }
}
