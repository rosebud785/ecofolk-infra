# main.tf — the one VPC that Cloud SQL private IP (ef#398) and Cloud Run (ef#400) both use (issue #1).
#
# What is here: one custom-mode VPC, one subnet in the pinned region, a Private Service Access (PSA)
# range, and the service-networking peering that lets Cloud SQL take a private IP inside that range.
#
# What is deliberately NOT here (issue #1, "not in scope"):
#   - no Serverless VPC Access connector: Cloud Run v2 uses Direct VPC egress straight into `subnet`,
#     which costs nothing while idle;
#   - no Cloud NAT;
#   - no firewall rules. A GCP VPC already denies all ingress, so "default-deny ingress" means adding
#     no allow rule here, not writing a deny rule.
#
# The compute and servicenetworking APIs this needs are enabled by modules/project; callers order the
# two with `depends_on` (see environments/dev/main.tf).
#
# LOCAL FOLLOW-UP: the tf-apply service account needs roles/compute.networkAdmin and
# roles/servicenetworking.networksAdmin on the project (or a role that includes them) before the first
# apply of this module. IAM is not managed in this public repo.
resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = var.name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "subnet" {
  project       = var.project_id
  name          = "${var.name}-${var.region}"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr

  # Lets Cloud Run (via Direct VPC egress) reach Google APIs without a public IP or NAT.
  private_ip_google_access = true
}

# The PSA range: Google's service producer network (Cloud SQL) allocates private IPs from here.
# `address` is left unset so GCP picks a free block of `psa_prefix_length` inside the VPC.
resource "google_compute_global_address" "psa" {
  project       = var.project_id
  name          = "${var.name}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.psa_prefix_length
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
}
