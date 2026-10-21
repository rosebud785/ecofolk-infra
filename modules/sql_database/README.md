# modules/sql_database

One environment's own database on an existing Cloud SQL instance (ecofolk-infra#13). The QA namespace
uses it for `ecofolk_qa` on dev's instance; it never creates an instance. The DB user is a name only
(`ecofolk_qa_app`): the user and its password are created out of band (LOCAL FOLLOW-UP L-SQL).

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
| [google_sql_database.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| env | Environment. Must be "qa" (#13): dev and prod get their database from modules/cloudsql. Names the database ecofolk_qa and the user ecofolk_qa_app. | `string` | n/a | yes |
| instance_name | Name of the existing Cloud SQL instance to create the database on (dev's, for qa). | `string` | n/a | yes |
| project_id | GCP project id that owns the instance (ecofolk-dev for qa). No default: every caller states its own project. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| database_name | The environment's database (ecofolk_qa). |
| resource_names | Every resource name this module sets, as <type>/<name> (#13's dev/qa collision test). |
| user_name | Name of the environment's own DB user (ecofolk_qa_app). Created out of band with its password, never here. |
<!-- END_TF_DOCS -->
