# The GCP project id comes from the §5 bootstrap output (repo variable GCP_PROJECT_ID, fed to Terraform
# as TF_VAR_project_id by infra.yml), not from a literal in source: the id may carry a suffix if
# "ecofolk-dev" was taken. No default, so a run that forgets it fails instead of guessing.
variable "project_id" {
  type        = string
  description = "GCP project id of the dev project (ecofolk-dev, or its suffixed form). Set from repo variable GCP_PROJECT_ID."
}
