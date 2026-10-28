# main.tf — the Cloud SQL schema migrator as a Cloud Run v2 Job (ecofolk#1169, G1 part 1 of 3).
#
# What is here: one Cloud Run Job, `ecofolk-migrate`, that runs the SAME image as the API (the app row
# supplies the migrator entrypoint; the deploy script's row updates this job's image to the pushed digest and
# executes it with --wait before `gcloud run deploy`). It reaches Cloud SQL's private IP through Direct VPC
# egress into the same subnet as modules/cloudrun_api, and runs as its own keyless service account, passed in.
# Database access is IAM auth: the job's SA is a Cloud SQL IAM database user (modules/cloudsql,
# migrate_service_account_email), so there is no password and no secret_env here.
#
# The image defaults to Google's public placeholder and Terraform ignores later changes to it, as for the API:
# the deploy script owns the image.
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
#   5. In the database, once, as a Cloud SQL superuser (Terraform manages no grants): GRANT cloudsqlsuperuser to
#      the migrator IAM user, so it can CREATE EXTENSION postgis, vector; it then owns every object its
#      migrations create, i.e. the schema. The API's runtime DB user (today the POSTGRES_PASSWORD user) is
#      NOT the owner and gets DML only: ALTER DEFAULT PRIVILEGES FOR ROLE <migrator> IN SCHEMA public GRANT
#      SELECT, INSERT, UPDATE, DELETE ON TABLES (and USAGE, SELECT ON SEQUENCES) TO that user. A grant
#      migration would have to run as a role that can already grant, so the default-privileges route is the
#      one used here.
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
        image = var.image

        dynamic "env" {
          for_each = var.env_vars
          content {
            name  = env.key
            value = env.value
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].template[0].containers[0].image]
  }
}
