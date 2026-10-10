# Cost and safety guards over the committed HCL (ecofolk-infra#7). PR CI holds no credentials, so these
# rules read the Terraform source, not a plan:
#
#   conftest test --parser hcl2 --combine --policy policy --data policy/data.json \
#     $(bash scripts/policy-files.sh)
#
# scripts/policy-files.sh lists every tracked *.tf in the repo and fails on any tracked *.tf.json, which
# the hcl2 parser can't read.
#
# --combine makes `input` one array of {path, contents}, so a rule can see which file a resource is in:
# the dev/prod limits and the local-only/ IAM exemption are decided by path.
#
# An argument a rule constrains must be a literal. "${var.x}" cannot be checked before a plan, so it is
# refused, not trusted.
#
# Surface path (CODEOWNERS): weakening any rule here needs ARCHITECT APPROVED.
package main

# Every resource block in every file, flattened. The hcl2 parser gives
# resource.<type>.<name> = [<body>].
resources contains r if {
	some f in input
	some rtype, by_name in f.contents.resource
	some rname, bodies in by_name
	some body in bodies
	r := {"path": f.path, "type": rtype, "name": rname, "body": body}
}

# environments/prod/ gets the prod limits. Everything else, including modules/ (which dev may call),
# gets the stricter dev limits.
is_prod(path) if regex.match(`(^|/)environments/prod/`, path)

label(r) := sprintf("%s: %s.%s", [r.path, r.type, r.name])
