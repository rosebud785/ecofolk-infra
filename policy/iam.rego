# The cloud-worker IAM boundary, made mechanical: no service-account key anywhere, and no *_iam_*
# resource (bindings, members, policies, custom roles, WIF pools/providers) outside a local-only/ path.
# Cloud sessions write neither; a human-side session adds them under local-only/.
package main

deny contains msg if {
	some r in resources
	r.type == "google_service_account_key"
	msg := sprintf("%s: google_service_account_key is forbidden everywhere (keyless only)", [label(r)])
}

deny contains msg if {
	some r in resources
	contains(r.type, "_iam_")
	not regex.match(`(^|/)local-only/`, r.path)
	msg := sprintf("%s: IAM resources belong under a local-only/ path", [label(r)])
}
