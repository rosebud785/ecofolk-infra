# modules/network

VPC, subnet, and Private Service Access for Cloud SQL private IP (ecofolk-infra#1).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| google | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| google | ~> 5.0 |

## Resources

| Name | Type |
|------|------|
| [google_compute_global_address.psa](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_global_address) | resource |
| [google_compute_network.vpc](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network) | resource |
| [google_compute_subnetwork.subnet](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork) | resource |
| [google_service_networking_connection.psa](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_networking_connection) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name of the VPC; also the prefix of the subnet and PSA range names. | `string` | `"ecofolk"` | no |
| project_id | GCP project id the network lives in. | `string` | n/a | yes |
| psa_prefix_length | Prefix length of the Private Service Access range. Between 20 and 24 inclusive. | `number` | `20` | no |
| region | GCP region for the subnet. Must be northamerica-northeast1 (ef#391); pass module.project.region. | `string` | n/a | yes |
| subnet_cidr | Primary IPv4 range of the subnet in var.region. | `string` | `"10.10.0.0/24"` | no |

## Outputs

| Name | Description |
|------|-------------|
| network_id | Relative resource name (.id) of the VPC (Cloud Run v2 vpc_access network). |
| network_self_link | Self-link of the VPC (Cloud SQL private_network). |
| subnet_id | Relative resource name (.id) of the subnet (Cloud Run v2 Direct VPC egress subnetwork). |
| subnet_self_link | Self-link of the subnet. |
<!-- END_TF_DOCS -->
