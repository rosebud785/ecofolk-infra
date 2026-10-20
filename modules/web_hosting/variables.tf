variable "project_id" {
  type        = string
  description = "GCP project id to add Firebase to and host the web build in. The site id is <project_id>-web."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a GCP project id: 6-30 lowercase letters, digits or hyphens, starting with a letter."
  }
}

# #13: dev, qa or prod. Neither resource here takes labels, so it only suffixes the site id: dev and prod
# each own a project, so their ids stay as they are; a qa call would get <project>-web-qa. qa doesn't call
# this module today, and google_firebase_project is one per project, so a qa call would also collide there.
variable "env" {
  type        = string
  description = "Environment: dev, qa or prod. Neither resource takes labels; qa (a namespace inside ecofolk-dev, #13) suffixes the site id with -qa."

  validation {
    condition     = contains(["dev", "qa", "prod"], var.env)
    error_message = "env must be \"dev\", \"qa\" or \"prod\"."
  }
}
