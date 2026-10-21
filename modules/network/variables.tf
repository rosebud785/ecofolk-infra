variable "project_id" {
  type        = string
  description = "GCP project id the network lives in."
}

# No default: the caller passes module.project.region, so modules/project/variables.tf stays the single
# source of truth for the region pin (ef#391). The validation is the same hard constraint, enforced here
# too so this module can never be pointed anywhere else.
variable "region" {
  type        = string
  description = "GCP region for the subnet. Must be northamerica-northeast1 (ef#391); pass module.project.region."

  validation {
    condition     = var.region == "northamerica-northeast1"
    error_message = "region must be \"northamerica-northeast1\" (Montréal) — a hard constraint. See ef#391."
  }
}

variable "name" {
  type        = string
  default     = "ecofolk"
  description = "Name of the VPC; also the prefix of the subnet and PSA range names."
}

# A /24 holds Direct VPC egress for Cloud Run (which needs at least a /26) with headroom.
variable "subnet_cidr" {
  type        = string
  default     = "10.10.0.0/24"
  description = "Primary IPv4 range of the subnet in var.region."

  validation {
    condition     = can(cidrnetmask(var.subnet_cidr))
    error_message = "subnet_cidr must be an IPv4 CIDR block, e.g. 10.10.0.0/24."
  }
}

# Issue #1 AC: the PSA range is /20 or smaller. Cloud SQL needs at least a /24.
variable "psa_prefix_length" {
  type        = number
  default     = 20
  description = "Prefix length of the Private Service Access range. Between 20 and 24 inclusive."

  validation {
    condition     = var.psa_prefix_length >= 20 && var.psa_prefix_length <= 24
    error_message = "psa_prefix_length must be between 20 and 24 (a /20 or smaller, and at least the /24 Cloud SQL needs)."
  }
}

# #13: dev, qa or prod. It is the PSA range's `env` label (the VPC and subnet take no labels) and it
# suffixes each resource name: dev and prod each own a project, so their names stay as they are; a qa
# call would end in -qa. qa reuses dev's network today and doesn't call this module.
variable "env" {
  type        = string
  description = "Environment: dev, qa or prod. Sets the `env` label; qa (a namespace inside ecofolk-dev, #13) also suffixes each resource name with -qa."

  validation {
    condition     = contains(["dev", "qa", "prod"], var.env)
    error_message = "env must be \"dev\", \"qa\" or \"prod\"."
  }
}
