# Issue #19 AC: with a mock provider (no credentials, no GCP), assert the region, min 0, max <= 3, Direct
# VPC egress PRIVATE_RANGES_ONLY through network_interfaces, the image ignore_changes, and that the module
# declares no *_iam_* resource.
mock_provider "google" {}

variables {
  project_id      = "ecofolk-dev"
  env             = "dev"
  service_account = "ecofolk-api@ecofolk-dev.iam.gserviceaccount.com"
  # Relative resource names (.id), as module.network's network_id/subnet_id outputs are; Cloud Run v2
  # rejects an https self-link here (#45).
  # (.tftest.hcl files are outside scripts/check-region-pin.sh's *.tf/*.tfvars scan.)
  network    = "projects/ecofolk-dev/global/networks/ecofolk"
  subnetwork = "projects/ecofolk-dev/regions/northamerica-northeast1/subnetworks/ecofolk-northamerica-northeast1"
}

run "is_in_the_pinned_region_with_public_ingress" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.api.location == "northamerica-northeast1"
    error_message = "service must be in northamerica-northeast1"
  }

  assert {
    condition     = google_cloud_run_v2_service.api.ingress == "INGRESS_TRAFFIC_ALL"
    error_message = "ingress must be INGRESS_TRAFFIC_ALL (it is the public API)"
  }

  assert {
    condition     = google_cloud_run_v2_service.api.project == "ecofolk-dev" && google_cloud_run_v2_service.api.name == "ecofolk-api"
    error_message = "service must be ecofolk-api on var.project_id"
  }
}

run "scales_to_zero_with_max_3" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.api.template[0].scaling[0].min_instance_count == 0
    error_message = "min_instance_count must be 0 (scale to zero)"
  }

  assert {
    condition     = google_cloud_run_v2_service.api.template[0].scaling[0].max_instance_count == 3
    error_message = "max_instance_count must default to 3"
  }
}

run "max_follows_the_variable" {
  command = plan

  variables {
    max_instance_count = 2
  }

  assert {
    condition     = google_cloud_run_v2_service.api.template[0].scaling[0].max_instance_count == 2
    error_message = "max_instance_count must come from var.max_instance_count"
  }
}

run "rejects_max_above_3" {
  command = plan

  variables {
    max_instance_count = 4
  }

  expect_failures = [var.max_instance_count]
}

run "egress_is_direct_vpc_private_ranges_only" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.api.template[0].vpc_access[0].egress == "PRIVATE_RANGES_ONLY"
    error_message = "vpc_access.egress must be PRIVATE_RANGES_ONLY"
  }

  assert {
    condition     = length(google_cloud_run_v2_service.api.template[0].vpc_access[0].network_interfaces) == 1
    error_message = "Direct VPC egress must use exactly one network_interfaces block"
  }

  assert {
    condition     = google_cloud_run_v2_service.api.template[0].vpc_access[0].network_interfaces[0].network == var.network && google_cloud_run_v2_service.api.template[0].vpc_access[0].network_interfaces[0].subnetwork == var.subnetwork
    error_message = "network_interfaces must take the network and subnetwork passed in"
  }

  assert {
    condition     = google_cloud_run_v2_service.api.template[0].vpc_access[0].connector == null
    error_message = "no Serverless VPC Access connector: Direct VPC egress only"
  }
}

run "container_settings" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.api.template[0].containers[0].image == "us-docker.pkg.dev/cloudrun/container/hello"
    error_message = "image must default to the public placeholder"
  }

  assert {
    condition     = google_cloud_run_v2_service.api.template[0].containers[0].ports[0].container_port == 8080
    error_message = "container port must be 8080"
  }

  assert {
    condition     = google_cloud_run_v2_service.api.template[0].containers[0].resources[0].cpu_idle == true
    error_message = "cpu_idle must be true"
  }

  assert {
    condition     = google_cloud_run_v2_service.api.template[0].timeout == "60s"
    error_message = "request timeout must be 60s"
  }

  assert {
    condition     = google_cloud_run_v2_service.api.template[0].service_account == var.service_account
    error_message = "service_account must be the runtime SA passed in"
  }

  assert {
    condition     = length(google_cloud_run_v2_service.api.template[0].containers[0].env) == 0
    error_message = "env_vars must default to empty"
  }
}

run "env_vars_follows_the_variable" {
  command = plan

  variables {
    env_vars = {
      NODE_ENV  = "production"
      LOG_LEVEL = "info"
    }
  }

  assert {
    condition = (
      length(google_cloud_run_v2_service.api.template[0].containers[0].env) == 2 &&
      alltrue([
        for e in google_cloud_run_v2_service.api.template[0].containers[0].env :
        lookup(var.env_vars, e.name, null) == e.value
      ])
    )
    error_message = "env must hold exactly the plain name/value pairs of var.env_vars"
  }
}

# A lifecycle block isn't visible in the plan, so read the module's own source instead.
run "image_changes_are_ignored" {
  command = plan

  assert {
    condition = anytrue([
      for f in fileset(path.module, "*.tf") :
      can(regex("ignore_changes\\s*=\\s*\\[\\s*template\\[0\\]\\.containers\\[0\\]\\.image\\s*\\]", file("${path.module}/${f}")))
    ])
    error_message = "the service must ignore_changes = [template[0].containers[0].image] so deploys own the image"
  }
}

run "declares_no_iam_resource" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") :
      !can(regex("resource\\s+\"[a-z0-9_]*_iam_[a-z0-9_]*\"", file("${path.module}/${f}")))
    ])
    error_message = "the module must not declare any *_iam_* resource (IAM is local follow-up L-RUN)"
  }
}

run "outputs" {
  command = apply

  assert {
    condition     = output.name == "ecofolk-api"
    error_message = "name output must be the service name"
  }

  assert {
    condition     = output.uri == google_cloud_run_v2_service.api.uri
    error_message = "uri output must be the service URI"
  }
}

run "rejects_another_region" {
  command = plan

  variables {
    region = "northamerica-northeast2"
  }

  expect_failures = [var.region]
}

run "rejects_a_non_service_account_email" {
  command = plan

  variables {
    service_account = "someone@example.com"
  }

  expect_failures = [var.service_account]
}

# #45: an https self-link 400s at the Cloud Run v2 API, so the validations must refuse one at plan.
run "rejects_a_network_self_link" {
  command = plan

  variables {
    network = "https://www.googleapis.com/compute/v1/projects/ecofolk-dev/global/networks/ecofolk"
  }

  expect_failures = [var.network]
}

run "rejects_a_subnetwork_self_link" {
  command = plan

  variables {
    subnetwork = "https://www.googleapis.com/compute/v1/projects/ecofolk-dev/regions/northamerica-northeast1/subnetworks/ecofolk-northamerica-northeast1"
  }

  expect_failures = [var.subnetwork]
}

# Issue #13: env. dev keeps the service name; qa gets -qa; the env label follows var.env.

run "env_dev_keeps_its_names_and_labels" {
  command = plan

  assert {
    condition     = google_cloud_run_v2_service.api.name == "ecofolk-api"
    error_message = "dev must keep the service name ecofolk-api"
  }

  assert {
    condition     = google_cloud_run_v2_service.api.labels.env == "dev"
    error_message = "the service must carry env = dev"
  }

  assert {
    condition     = output.resource_names == ["google_cloud_run_v2_service/ecofolk-api"]
    error_message = "resource_names must be every name the module sets (#13), got ${jsonencode(output.resource_names)}"
  }
}

run "env_qa_suffixes_names_and_labels" {
  command = plan

  variables {
    env = "qa"
  }

  assert {
    condition     = google_cloud_run_v2_service.api.name == "ecofolk-api-qa" && output.name == "ecofolk-api-qa"
    error_message = "qa must name the service ecofolk-api-qa"
  }

  assert {
    condition     = google_cloud_run_v2_service.api.labels.env == "qa"
    error_message = "the service must carry env = qa"
  }

  assert {
    condition     = output.resource_names == ["google_cloud_run_v2_service/ecofolk-api-qa"]
    error_message = "resource_names must be every name the module sets (#13), got ${jsonencode(output.resource_names)}"
  }
}

run "env_refuses_staging" {
  command = plan

  variables {
    env = "staging"
  }

  expect_failures = [var.env]
}
