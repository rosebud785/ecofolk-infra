# Secret Manager (ecofolk-infra#32, Architect ruling on ecofolk#399): this public repo creates secret
# CONTAINERS only. A google_secret_manager_secret_version holds a secret's value, which would land in the
# repo and in the keyless apply's state, so it is refused outside a local-only/ path; values are added
# locally (ecofolk#936). Accessor bindings (google_secret_manager_secret_iam_*) are refused outside
# local-only/ too (ecofolk#890); iam.rego's general *_iam_* rule also catches them.
package main

forbidden_secret_type(t) if t == "google_secret_manager_secret_version"

forbidden_secret_type(t) if startswith(t, "google_secret_manager_secret_iam_")

deny contains msg if {
	some r in resources
	forbidden_secret_type(r.type)
	not regex.match(`(^|/)local-only/`, r.path)
	msg := sprintf("%s: Secret Manager versions (values) and secret IAM belong under a local-only/ path; this repo creates secret containers only", [label(r)])
}
