# Issue #1 AC: with a mock provider (no credentials, no GCP), assert the subnet region and that the PSA
# range is /20 or smaller.
mock_provider "google" {}

variables {
  project_id = "ecofolk-dev"
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
