# Cloud Run: scale to zero, and a hard ceiling on instances (≤ 3 dev, ≤ 5 prod). Cloud Run's own default
# max is 100, so an unset max_instance_count is refused, not assumed small.
package main

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
