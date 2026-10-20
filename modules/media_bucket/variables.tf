# Same region pin as modules/project/variables.tf (ef#391): the validation refuses any other value, and
# scripts/check-region-pin.sh covers anything hardcoded around it.
variable "region" {
  type        = string
  default     = "northamerica-northeast1" # Montréal — do not change (ef#391)
  description = "Bucket location (lower-case; the bucket gets it upper-cased). Must always be northamerica-northeast1 (Montréal), ef#391."

  validation {
    condition     = var.region == "northamerica-northeast1"
    error_message = "region must be \"northamerica-northeast1\" (Montréal) — this is a hard constraint, not a default to change. See ef#391."
  }
}

variable "project_id" {
  type        = string
  description = "GCP project id that owns the bucket. The bucket is named <project_id>-media (globally unique). No default."
}

# #13: dev, qa or prod. qa uses a prefix in dev's bucket rather than calling this module, but a qa call
# would get its own <project_id>-media-qa bucket, never dev's.
variable "env" {
  type        = string
  description = "Environment: dev, qa or prod. Sets the `env` label; qa (a namespace inside ecofolk-dev, #13) also suffixes each resource name with -qa."

  validation {
    condition     = contains(["dev", "qa", "prod"], var.env)
    error_message = "env must be \"dev\", \"qa\" or \"prod\"."
  }
}
