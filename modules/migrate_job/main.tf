# main.tf — the Cloud SQL schema migrator as a Cloud Run v2 Job (ecofolk#1169, G1 part 1 of 3).
#
# What is here: one Cloud Run Job, `ecofolk-migrate`, that runs the SAME image as the API (the app row
# supplies the migrator entrypoint; the deploy script's row updates this job's image to the pushed digest and
# executes it with --wait before `gcloud run deploy`). It reaches Cloud SQL's private IP through Direct VPC
# egress into the same subnet as modules/cloudrun_api, and runs as its own keyless service account, passed in.
# Database access is IAM auth: the job's SA is a Cloud SQL IAM database user (modules/cloudsql,
# migrate_service_account_email), so the job holds no DB LOGIN secret. Its ONE secret_env is
# POSTGRES_INGEST_PASSWORD: the value the migrator sets on the ecofolk_ingest role (migration 016), not a login
# (Architect, ecofolk#1180 ruling (3)); var.secret_env refuses any other name.
#
# Who owns what (Architect, T1): TERRAFORM owns the job's command/args (static: node + the migrate CLI), so the
# next apply cannot revert them; the DEPLOY SCRIPT owns the image only (`gcloud run jobs update --image`).
# The image defaults to Google's public placeholder, which never executes: only the deploy script runs the job,
# after it sets the real image. Terraform ignores later changes to the image alone, as for the API.
#
# What is deliberately NOT here (the public-repo boundary, CONTRIBUTING.md): no IAM of any kind.
#
# LOCAL FOLLOW-UP (ecofolk#1169), IAM is not managed in this public repo; a local session adds, in this order:
#   1. Create the service account var.service_account (`ecofolk-migrate`) with NO key.
#   2. roles/cloudsql.client and roles/cloudsql.instanceUser for it on the project (IAM DB auth to the instance).
#   3. roles/iam.serviceAccountUser for tf-apply ON THAT ONE SERVICE ACCOUNT (without it the first apply 403s
#      on iam.serviceaccounts.actAs, as for the API, #44), and for `ecofolk-deploy` on it (the deploy script
#      updates and executes the job as that identity).
#   4. roles/run.developer for `ecofolk-deploy` on THIS JOB ONLY (google_cloud_run_v2_job_iam_member), never
#      project-wide.
#   5. roles/secretmanager.secretAccessor for it on the POSTGRES_INGEST_PASSWORD secret ONLY (a secret ref it
#      cannot read blocks the apply, as for the API's, ecofolk#890).
#   6. The migrator's cloudsqlsuperuser membership (CREATE EXTENSION postgis, vector), by the Cloud SQL Admin API,
#      no SQL session: `gcloud sql users assign-roles <migrator> --instance=ecofolk-pg
#      --type=CLOUD_IAM_SERVICE_ACCOUNT --database-roles=cloudsqlsuperuser`. Architect's ruling (ecofolk#1180, 2a)
#      wanted google_sql_user.database_roles; the pinned hashicorp/google 5.45.2 has no such argument, so this is
#      the ruling's own fallback. Idempotent; belongs in the pre-merge paste (before #1180's first run).
# The runtime user's DML grants are not here: they are the migrate CLI's own post-step (ecofolk#1180).
locals {
  # #13: dev and prod keep their names (each owns its project); a namespace env (qa) gets -<env>.
  env_suffix = contains(["dev", "prod"], var.env) ? "" : "-${var.env}"
}

resource "google_cloud_run_v2_job" "migrate" {
  project  = var.project_id
  name     = "${var.name}${local.env_suffix}"
  location = var.region

  labels = {
    env = var.env
  }

  template {
    # One task, no parallelism: migrations apply in order and must not race.
    parallelism = 1
    task_count  = 1

    template {
      service_account = var.service_account
      timeout         = "${var.timeout_seconds}s"
      # A failed migration is not retried: the deploy script reads the failure and refuses to deploy.
      max_retries = 0

      # Direct VPC egress, as modules/cloudrun_api: only private ranges (Cloud SQL's PSA IP) go through the VPC.
      vpc_access {
        egress = "PRIVATE_RANGES_ONLY"
        network_interfaces {
          network    = var.network
          subnetwork = var.subnetwork
        }
      }

      containers {
        image   = var.image
        command = var.command
        args    = var.args

        dynamic "env" {
          for_each = var.env_vars
          content {
            name  = env.key
            value = env.value
          }
        }

        # The one secret ref (see the header): by reference only, never a literal.
        dynamic "env" {
          for_each = var.secret_env
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = env.value
                version = "latest"
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].template[0].containers[0].image]
  }
}
