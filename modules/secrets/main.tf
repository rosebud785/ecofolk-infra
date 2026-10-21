# main.tf — Secret Manager secret CONTAINERS for the API, in Montréal (ecofolk-infra#32, ecofolk#399).
#
# What is here: one google_secret_manager_secret per name in var.secret_names, and nothing else. A secret
# is only a named, empty container; its value is a secret VERSION, and this public repo never writes one.
# Names aren't values. C7 (policy/secrets.rego) refuses any google_secret_manager_secret_version outside
# local-only/, so a value can't land in this repo or in the keyless apply's state.
#
# Replication is user-managed with a single replica in var.region (validated to northamerica-northeast1,
# ef#391): automatic replication would place copies outside Montréal and break the region pin.
#
# The names are a contract: a later human-run script grants access to exactly these names, and the API
# will read env vars of the same names (the Cloud Run secretKeyRef mapping is ecofolk-infra#66). Never rename.
#
# Needs secretmanager.googleapis.com (modules/project); callers order it with `depends_on`.
#
# LOCAL FOLLOW-UP (ecofolk#936): add each secret's VALUE (a version) by hand. Nothing references these
# secrets yet; the Cloud Run mapping (ecofolk-infra#66) waits on these values and the accessors below.
# LOCAL FOLLOW-UP (L-RUN, ecofolk#890): roles/secretmanager.secretAccessor for the API's runtime service
# account, on each of these secrets only (google_secret_manager_secret_iam_member, never project-wide).
# IAM is never written in this repo by a cloud session.
locals {
  # #13: dev and prod keep the contract names (each owns its project); a namespace env (qa) gets _<ENV>,
  # since secret ids are env-var-style.
  env_suffix = contains(["dev", "prod"], var.env) ? "" : "-${var.env}"
}

resource "google_secret_manager_secret" "secret" {
  for_each = toset(var.secret_names)

  project   = var.project_id
  secret_id = "${each.value}${upper(replace(local.env_suffix, "-", "_"))}"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  labels = {
    env       = var.env
    component = "api"
  }
}
