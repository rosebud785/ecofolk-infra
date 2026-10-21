# main.tf — the EcoFolk API on Cloud Run v2, scale-to-zero, in Montréal (ecofolk-infra#19, ef#400).
#
# What is here: one Cloud Run v2 service, public ingress, that scales to zero (min 0, max var-capped at 3
# by C7), reaches Cloud SQL's private IP through Direct VPC egress into modules/network's subnet (no
# connector), and runs as the runtime service account passed in.
#
# The image defaults to Google's public placeholder and Terraform ignores later changes to it: deploys
# (ef#408, local) set the real image, and a later apply must not roll it back.
#
# Secrets (ecofolk-infra#66): `secret_env` maps env var names to Secret Manager secret ids, each as a
# value_source { secret_key_ref } at version "latest". No value is ever written here; `env_vars` stays
# non-secret values only. The module takes the list as a variable so a future secret is added by the caller.
#
# What is deliberately NOT here (Architect spec on #19):
#   - no IAM of any kind: the runtime service account, the apply identity's actAs on it, and the
#     `allUsers` -> roles/run.invoker binding that makes the API callable are local follow-up (L-RUN below);
#   - no custom domain or domain mapping (ef#404/#670), and no deploy CI (ef#408).
#
# Needs run.googleapis.com (modules/project) and the subnet (modules/network); callers order them with
# `depends_on` (see environments/dev/main.tf).
#
# LOCAL FOLLOW-UP (L-RUN), in this order (ecofolk-infra#44):
#   1. Create the runtime service account (environments/dev passes its email) with NO roles at this stage.
#   2. Grant the apply identity (tf-apply) roles/iam.serviceAccountUser ON THAT ONE SERVICE ACCOUNT only,
#      never project-wide; without it the first apply 403s on iam.serviceaccounts.actAs (#19).
#   3. Deferred: the `allUsers` -> roles/run.invoker binding on this service to ef#408 (first real deploy),
#      then the cold start measurement (first-request latency after scale-to-zero, 5 runs, report the
#      median) once the real image is deployed; roles/cloudsql.client and
#      roles/secretmanager.secretAccessor (per named secret) to ef#399.
locals {
  # #13: dev and prod keep their names (each owns its project); a namespace env (qa) gets -<env>.
  env_suffix = contains(["dev", "prod"], var.env) ? "" : "-${var.env}"
}

resource "google_cloud_run_v2_service" "api" {
  project  = var.project_id
  name     = "${var.name}${local.env_suffix}"
  location = var.region

  labels = {
    env = var.env
  }

  # The public API: reachable from the internet once allUsers gets the invoker role (L-RUN, ef#408).
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.service_account
    timeout         = "60s"

    # max_instance_count is exactly var.max_instance_count: C7b (#39, policy/module_vars.rego) checks its
    # literal default and every call site's value against the instance cap.
    scaling {
      min_instance_count = 0
      max_instance_count = var.max_instance_count
    }

    # Direct VPC egress: only private ranges (Cloud SQL's PSA IP) go through the VPC; the rest goes out
    # directly, so no NAT is needed.
    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = var.network
        subnetwork = var.subnetwork
      }
    }

    containers {
      image = var.image

      ports {
        container_port = 8080
      }

      resources {
        # CPU only while a request is in flight: idle instances bill nothing for CPU.
        cpu_idle = true
      }

      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      # Secret-backed env vars (#66): by reference only, never a literal.
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

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }
}
