# Module sources: local paths only. The rules here read resource blocks, so a registry, git or https
# module would create *_iam_* or Cloud Run resources the policy never sees. A local module is just more
# tracked *.tf, which the policy job already scans (scripts/policy-files.sh). A vetted remote module, if
# one is ever wanted, becomes an explicit allowlist entry in data.json (surface).
package main

modules contains m if {
	some f in input
	some mname, bodies in f.contents.module
	some body in bodies
	m := {"path": f.path, "name": mname, "body": body}
}

local_source(s) if startswith(s, "./")

local_source(s) if startswith(s, "../")

deny contains msg if {
	some m in modules
	src := object.get(m.body, "source", "<unset>")
	not local_source(src)
	msg := sprintf("%s: module.%s: source must be a local path (./ or ../), got %v", [m.path, m.name, src])
}
