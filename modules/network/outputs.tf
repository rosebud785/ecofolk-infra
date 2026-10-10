output "network_self_link" {
  value       = google_compute_network.vpc.self_link
  description = "Self-link of the VPC (Cloud SQL private_network, Cloud Run v2 vpc_access network)."
}

output "subnet_self_link" {
  value       = google_compute_subnetwork.subnet.self_link
  description = "Self-link of the subnet (Cloud Run v2 Direct VPC egress subnetwork)."
}
