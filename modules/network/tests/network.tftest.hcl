# Issue #1 AC: with a mock provider (no credentials, no GCP), assert the subnet region and that the PSA
# range is /20 or smaller.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
  env        = "dev"
  region     = "northamerica-northeast1"
}

run "subnet_is_in_the_pinned_region" {
  command = plan

  assert {
    condition     = google_compute_subnetwork.subnet.region == "northamerica-northeast1"
    error_message = "subnet must be in northamerica-northeast1"
  }
}

run "psa_range_is_a_20_or_smaller" {
  command = plan

  assert {
    condition     = google_compute_global_address.psa.prefix_length >= 20
    error_message = "PSA range must be /20 or smaller"
  }

  assert {
    condition     = google_compute_global_address.psa.purpose == "VPC_PEERING" && google_compute_global_address.psa.address_type == "INTERNAL"
    error_message = "PSA range must be an INTERNAL VPC_PEERING address"
  }

  assert {
    condition     = google_service_networking_connection.psa.reserved_peering_ranges == tolist([google_compute_global_address.psa.name])
    error_message = "the service networking connection must reserve exactly the PSA range"
  }
}

run "vpc_is_custom_mode" {
  command = plan

  assert {
    condition     = google_compute_network.vpc.auto_create_subnetworks == false
    error_message = "VPC must be custom-mode (no auto-created subnets)"
  }
}

run "outputs_are_the_self_links" {
  command = apply

  assert {
    condition     = output.network_self_link == google_compute_network.vpc.self_link && output.network_self_link != ""
    error_message = "network_self_link must be the VPC's self-link"
  }

  assert {
    condition     = output.subnet_self_link == google_compute_subnetwork.subnet.self_link && output.subnet_self_link != ""
    error_message = "subnet_self_link must be the subnet's self-link"
  }
}

# #45: Cloud Run v2 takes the relative resource names (.id), not the self-links.
run "outputs_are_the_ids" {
  command = apply

  assert {
    condition     = output.network_id == google_compute_network.vpc.id && output.network_id != ""
    error_message = "network_id must be the VPC's .id"
  }

  assert {
    condition     = output.subnet_id == google_compute_subnetwork.subnet.id && output.subnet_id != ""
    error_message = "subnet_id must be the subnet's .id"
  }
}

run "rejects_another_region" {
  command = plan

  variables {
    region = "northamerica-northeast2"
  }

  expect_failures = [var.region]
}

run "rejects_a_psa_range_larger_than_20" {
  command = plan

  variables {
    psa_prefix_length = 16
  }

  expect_failures = [var.psa_prefix_length]
}

# ecofolk-infra#8: the subnet settings Cloud Run's Direct VPC egress relies on, and the CIDR guard.
run "subnet_defaults" {
  command = plan

  assert {
    condition     = google_compute_subnetwork.subnet.ip_cidr_range == "10.10.0.0/24"
    error_message = "subnet must default to 10.10.0.0/24"
  }

  assert {
    condition     = google_compute_subnetwork.subnet.private_ip_google_access == true
    error_message = "subnet must have Private Google Access on"
  }

  assert {
    condition     = google_compute_network.vpc.routing_mode == "REGIONAL"
    error_message = "VPC routing mode must be REGIONAL"
  }
}

run "rejects_a_non_cidr_subnet" {
  command = plan

  variables {
    subnet_cidr = "10.10.0.0"
  }

  expect_failures = [var.subnet_cidr]
}

# Issue #13: env. dev keeps every name; qa would suffix each; the PSA range carries the env label.

run "env_dev_keeps_its_names_and_labels" {
  command = plan

  assert {
    condition     = google_compute_network.vpc.name == "ecofolk" && google_compute_subnetwork.subnet.name == "ecofolk-northamerica-northeast1" && google_compute_global_address.psa.name == "ecofolk-psa"
    error_message = "dev must keep the VPC, subnet and PSA range names"
  }

  assert {
    condition     = google_compute_global_address.psa.labels.env == "dev"
    error_message = "the PSA range must carry env = dev"
  }

  assert {
    condition = output.resource_names == [
      "google_compute_network/ecofolk",
      "google_compute_subnetwork/ecofolk-northamerica-northeast1",
      "google_compute_global_address/ecofolk-psa",
    ]
    error_message = "resource_names must be every name the module sets (#13), got ${jsonencode(output.resource_names)}"
  }
}

run "env_qa_suffixes_names_and_labels" {
  command = plan

  variables {
    env = "qa"
  }

  assert {
    condition     = google_compute_network.vpc.name == "ecofolk-qa" && google_compute_subnetwork.subnet.name == "ecofolk-qa-northamerica-northeast1" && google_compute_global_address.psa.name == "ecofolk-qa-psa"
    error_message = "qa must suffix the VPC, subnet and PSA range names"
  }

  assert {
    condition     = google_compute_global_address.psa.labels.env == "qa"
    error_message = "the PSA range must carry env = qa"
  }

  assert {
    condition = output.resource_names == [
      "google_compute_network/ecofolk-qa",
      "google_compute_subnetwork/ecofolk-qa-northamerica-northeast1",
      "google_compute_global_address/ecofolk-qa-psa",
    ]
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
