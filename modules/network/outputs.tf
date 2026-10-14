output "network_self_link" {
  value       = google_compute_network.vpc.self_link
  description = "Self-link of the VPC (Cloud SQL private_network)."
}

output "subnet_self_link" {
  value       = google_compute_subnetwork.subnet.self_link
  description = "Self-link of the subnet."
}

# Cloud Run v2's vpc_access.network_interfaces wants the relative resource name (.id), not the https
# self-link: a self-link there 400s at create (ecofolk-infra#45).
output "network_id" {
  value       = google_compute_network.vpc.id
  description = "Relative resource name (.id) of the VPC (Cloud Run v2 vpc_access network)."
}

output "subnet_id" {
  value       = google_compute_subnetwork.subnet.id
  description = "Relative resource name (.id) of the subnet (Cloud Run v2 Direct VPC egress subnetwork)."
}
