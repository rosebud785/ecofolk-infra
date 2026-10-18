# modules/media_bucket

Private GCS media bucket in Montréal, with an abort-multipart lifecycle rule only (ecofolk-infra#21).

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
| [google_storage_bucket.media](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| env | Environment name, set as the bucket's `env` label. | `string` | n/a | yes |
| project_id | GCP project id that owns the bucket. The bucket is named <project_id>-media (globally unique). No default. | `string` | n/a | yes |
| region | Bucket location (lower-case; the bucket gets it upper-cased). Must always be northamerica-northeast1 (Montréal), ef#391. | `string` | `"northamerica-northeast1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| bucket_name | The media bucket's name (<project_id>-media). |
| bucket_url | The media bucket's gs:// URL. |
<!-- END_TF_DOCS -->
