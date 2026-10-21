# Same region pin as modules/project/variables.tf (ef#391): the validation refuses any other value, and
# scripts/check-region-pin.sh covers anything hardcoded around it.
variable "region" {
  type        = string
  default     = "northamerica-northeast1" # Montréal — do not change (ef#391)
  description = "Cloud Run region. Must always be northamerica-northeast1 (Montréal), ef#391; pass module.project.region."

  validation {
    condition     = var.region == "northamerica-northeast1"
    error_message = "region must be \"northamerica-northeast1\" (Montréal) — this is a hard constraint, not a default to change. See ef#391."
  }
}

variable "project_id" {
  type        = string
  description = "GCP project id that owns the service. No default: every caller states its own project."
}

variable "name" {
  type        = string
  default     = "ecofolk-api"
  description = "Cloud Run service name (lowercase letters, digits and hyphens). A qa service gets -qa appended (#13)."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,44}[a-z0-9])?$", var.name))
    error_message = "name must start with a lowercase letter and contain only lowercase letters, digits and hyphens (max 46 chars, so the -qa suffix still fits Cloud Run's 49)."
  }
}

# Only the initial image: deploys (ef#408) set the real one and the module ignores changes to it.
variable "image" {
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
  description = "Container image for the first revision. Defaults to Google's public placeholder; later deploys own the image."
}

# The policy (policy/module_vars.rego, #39) accepts var.max_instance_count only while this default is a
# literal within the cap (3 outside prod) and every caller omits it or passes a literal within its cap.
variable "max_instance_count" {
  type        = number
  default     = 3
  description = "Upper bound on instances. At most 3 (C7); callers pass a literal or omit it."

  validation {
    condition     = var.max_instance_count >= 1 && var.max_instance_count <= 3
    error_message = "max_instance_count must be between 1 and 3 (C7's dev cap)."
  }
}

variable "service_account" {
  type        = string
  description = "Email of the runtime service account the service runs as. Created locally (L-RUN), never here."

  validation {
    condition     = can(regex("^[^@\\s]+@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", var.service_account))
    error_message = "service_account must be a service account email (<id>@<project>.iam.gserviceaccount.com)."
  }
}

# Cloud Run v2 rejects an https self-link here with a 400 at create (ecofolk-infra#45), so the validations
# refuse one at plan. The network pattern's `[g]lobal` is the literal path segment, bracketed so that
# scripts/check-region-pin.sh's bare-word check (it refuses that word in *.tf) doesn't flag the pattern.
variable "network" {
  type        = string
  description = "VPC for Direct VPC egress, as its relative resource name (.id), not self-link; pass module.network.network_id."

  validation {
    condition     = can(regex("^projects/[^/]+/[g]lobal/networks/[^/]+$", var.network))
    error_message = "network must be the VPC's relative resource name (.id, projects/<project>/<scope>/networks/<name>), not an https self-link (ecofolk-infra#45)."
  }
}

variable "subnetwork" {
  type        = string
  description = "Subnet for Direct VPC egress, as its relative resource name (.id), not self-link; pass module.network.subnet_id."

  validation {
    condition     = can(regex("^projects/[^/]+/regions/[^/]+/subnetworks/[^/]+$", var.subnetwork))
    error_message = "subnetwork must be the subnet's relative resource name (.id, projects/<project>/regions/<region>/subnetworks/<name>), not an https self-link (ecofolk-infra#45)."
  }
}

# Non-secret values only. Secrets go in secret_env below.
# Named env_vars, not env, since #13: `env` is the environment name every module takes.
variable "env_vars" {
  type        = map(string)
  default     = {}
  description = "Plain environment variables for the container. NON-SECRET values only: this lands in state and in the public repo."
}

# #13: dev, qa or prod. It is each resource's `env` label (where the type takes labels) and it suffixes
# each resource name: dev and prod each own a project, so their names stay as they are; qa is a namespace
# inside ecofolk-dev, so its names end in -qa and can't collide with dev's.
variable "env" {
  type        = string
  description = "Environment: dev, qa or prod. Sets the `env` label; qa (a namespace inside ecofolk-dev, #13) also suffixes each resource name with -qa."

  validation {
    condition     = contains(["dev", "qa", "prod"], var.env)
    error_message = "env must be \"dev\", \"qa\" or \"prod\"."
  }
}

# ecofolk-infra#66. Env var name -> Secret Manager secret (id or relative name; pass module.secrets.secret_ids[...]).
# Each becomes a secret_key_ref at "latest": the revision fails readiness if the secret has no enabled version or
# the runtime SA lacks secretAccessor (ecofolk#936, #890), so a name is added here only once both hold.
variable "secret_env" {
  type        = map(string)
  default     = {}
  description = "Env var name -> Secret Manager secret, mapped by secret_key_ref at version latest. References only, never values."

  validation {
    condition     = alltrue([for k in keys(var.secret_env) : can(regex("^[A-Z][A-Z0-9_]*$", k))])
    error_message = "secret_env keys must be env-var-style names (upper-case letters, digits, underscores)."
  }

  validation {
    condition     = alltrue([for v in values(var.secret_env) : length(v) > 0])
    error_message = "secret_env values must be non-empty secret references."
  }
}
