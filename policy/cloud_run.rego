# Cloud Run: scale to zero, and a hard ceiling on instances (≤ 3 dev, ≤ 5 prod). Cloud Run's own default
# max is 100, so an unset max_instance_count is refused, not assumed small.
#
# Only the shapes the cap can read are allowed: v2 services (autoscaled) and v2 jobs (billed per
# execution). v1 services, worker pools and any other google_cloud_run* type are refused, and so is
# manual scaling on a v2 service (fixed instances, billed always-on). *_iam_* types belong to the IAM rule.
package main

allowed_run_types := {"google_cloud_run_v2_service", "google_cloud_run_v2_job"}

deny contains msg if {
	some r in resources
	startswith(r.type, "google_cloud_run")
	not r.type in allowed_run_types
	not contains(r.type, "_iam_")
	msg := sprintf("%s: only google_cloud_run_v2_service and google_cloud_run_v2_job are allowed (the instance cap can't read %s)", [label(r), r.type])
}

max_instances(path) := 5 if is_prod(path)

max_instances(path) := 3 if not is_prod(path)

# template.scaling and the service-level scaling block both count.
run_scaling(r) := array.concat(
	[s | some t in object.get(r.body, "template", []); some s in object.get(t, "scaling", [])],
	[s | some s in object.get(r.body, "scaling", [])],
)

run_services contains r if {
	some r in resources
	r.type == "google_cloud_run_v2_service"
}

deny contains msg if {
	some r in run_services
	some s in run_scaling(r)
	v := s.min_instance_count
	v != 0
	msg := sprintf("%s: min_instance_count must be the literal 0, got %v", [label(r), v])
}

deny contains msg if {
	some r in run_services
	some s in run_scaling(r)
	v := s.max_instance_count
	not is_number(v)
	msg := sprintf("%s: max_instance_count must be a literal number, got %v", [label(r), v])
}

deny contains msg if {
	some r in run_services
	some s in run_scaling(r)
	v := s.max_instance_count
	is_number(v)
	v > max_instances(r.path)
	msg := sprintf("%s: max_instance_count %v exceeds %v", [label(r), v, max_instances(r.path)])
}

deny contains msg if {
	some r in run_services
	count([s | some s in run_scaling(r); "max_instance_count" in object.keys(s)]) == 0
	msg := sprintf("%s: max_instance_count must be set (Cloud Run defaults to 100)", [label(r)])
}

deny contains msg if {
	some r in run_services
	some s in run_scaling(r)
	"manual_instance_count" in object.keys(s)
	msg := sprintf("%s: manual_instance_count is forbidden (fixed instances bypass the cap)", [label(r)])
}

deny contains msg if {
	some r in run_services
	some s in run_scaling(r)
	"scaling_mode" in object.keys(s)
	s.scaling_mode != "AUTOMATIC"
	msg := sprintf("%s: scaling_mode must be the literal \"AUTOMATIC\", got %v", [label(r), s.scaling_mode])
}
