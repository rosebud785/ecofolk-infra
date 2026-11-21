# main.tf — the pre-deploy config check as a Cloud Run v2 Job (ecofolk-infra#169, ecofolk#1419).
#
# What is here: one Cloud Run Job, `ecofolk-check-config`, that runs the SAME image as the API with `node
# dist/checkConfig.js`: loadApiConfig plus a SELECT 1 as the runtime and the ingest database user. The deploy
# script (ecofolk scripts/deploy/deploy-dev.sh, step 3b) updates this job's image to the pushed digest and
# executes it with --wait BEFORE the migrate job and `gcloud run deploy`; a failing execution refuses the deploy.
#
# It proves nothing unless it runs as the service does. So the caller passes the SAME env_vars, secret_env and
# service account it passes to modules/cloudrun_api, from one shared local (environments/dev/main.tf), and the same
# network and subnet: Direct VPC egress, as the API, so Cloud SQL's private IP is reachable. The job holds no
# secret or permission the service does not already have, and nothing here grants any.
#
# Who owns what (as modules/migrate_job): TERRAFORM owns the command and args, static, so the next apply cannot
# revert them; the DEPLOY SCRIPT owns the image only (`gcloud run jobs update --image`). The image defaults to
# Google's public placeholder, which never executes: only the deploy script runs the job, after it sets the real
# image. Terraform ignores later changes to the image alone.
#
# What is deliberately NOT here (the public-repo boundary, CONTRIBUTING.md): no IAM of any kind. The job runs as the
# API's runtime service account, which already has what the service has (secretAccessor on its secrets,
# cloudsql.client); the apply identity's actAs on it exists for the service already. The only new binding is the
# deploy identity's, a local follow-up:
#   - roles/run.developer for `ecofolk-deploy` on THIS JOB ONLY (google_cloud_run_v2_job_iam_member), never
#     project-wide; the deploy script updates and executes the job as that identity. `ecofolk-deploy` also needs
#     roles/iam.serviceAccountUser on the API's runtime service account (a job that runs as it is an actAs), if it
#     does not already hold it for the service deploy.
locals {
  # #13: dev and prod keep their names (each owns its project); a namespace env (qa) gets -<env>.
  env_suffix = contains(["dev", "prod"], var.env) ? "" : "-${var.env}"
}

resource "google_cloud_run_v2_job" "check_config" {
  project  = var.project_id
  name     = "${var.name}${local.env_suffix}"
  location = var.region

  labels = {
    env = var.env
  }

  template {
    # One task, no parallelism: one check, one answer.
    parallelism = 1
    task_count  = 1

    template {
      service_account = var.service_account
      timeout         = "${var.timeout_seconds}s"
      # A failed check is not retried: the deploy script reads the failure and refuses to deploy.
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

        # Secret-backed env vars: by reference only, never a literal. The same refs the service maps.
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
    ignore_changes = [template[0].template[0].containers[0].image, client, client_version]
  }
}
