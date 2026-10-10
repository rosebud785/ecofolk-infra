# Module-aware limits (ecofolk-infra#39, C7b). A constrained argument written directly in a file under
# modules/<m>/ whose value is exactly "${var.X}" is judged by what X can actually be, instead of being
# refused for not being a literal. It is accepted only if both hold:
#
#   1. modules/<m> declares variable "X" with a literal default that passes under the dev limits;
#   2. every module block anywhere whose source resolves to modules/<m> either omits X (the default is
#      then judged under the call site's limits) or passes a literal that passes under the call site's
#      limits. environments/prod/** gets the prod limits; anything else gets the dev limits.
#
# Any other expression (var.X with no default, locals, conditionals, "${var.X}-suffix", a variable used
# outside modules/<m>/ itself) is refused by the rule that owns the argument, as before. Each owning rule
# lists its arguments in `constrained` and says what passes in `limit_ok` / `limit_text`.
#
# A local module source is resolved by normalising the call site's directory + the relative path; one that
# doesn't resolve to a directory holding a tracked *.tf is refused (modules.rego), so no call site can
# hide from rule 2.
package main

# Directory part of a path, unnormalised: "a/b/c.tf" -> "a/b", "c.tf" -> "".
raw_dir(path) := concat("/", array.slice(parts, 0, count(parts) - 1)) if parts := split(path, "/")

# Path segments with empty and "." segments dropped.
path_segments(p) := [s | some s in split(p, "/"); s != ""; s != "."]

seg_step(s) := -1 if s == ".."

seg_step(s) := 1 if s != ".."

# Depth after segment j (segments 0..j). A ".." cancels the nearest earlier name it isn't already paired with.
seg_depth(segs, j) := sum([seg_step(segs[k]) | some k, _ in segs; k <= j])

# Normalised, repo-relative path ("" is the repo root). Undefined if it climbs above the root.
normalise(p) := concat("/", kept) if {
	segs := path_segments(p)
	count([j | some j, _ in segs; seg_depth(segs, j) < 0]) == 0
	kept := [s |
		some i, s in segs
		s != ".."
		count([j | some j, _ in segs; j > i; seg_depth(segs, j) <= seg_depth(segs, i - 1)]) == 0
	]
}

file_dir(path) := normalise(raw_dir(path))

# Every directory that holds a tracked *.tf (the policy job's input is exactly those files).
tracked_dirs contains d if {
	some f in input
	d := file_dir(f.path)
}

# The directory a module block's local source resolves to. Undefined for a non-local source or one that
# climbs above the repo root.
module_target(m) := normalise(concat("/", [raw_dir(m.path), m.body.source])) if {
	is_string(m.body.source)
	local_source(m.body.source)
}

# X, when v is exactly "${var.X}" and r is in a file directly under modules/<m>/.
module_var_name(r, v) := name if {
	is_string(v)
	regex.match(`^modules/[^/]+$`, file_dir(r.path))
	match := regex.find_all_string_submatch_n(`^\$\{var\.([A-Za-z_][A-Za-z0-9_-]*)\}$`, v, 1)
	name := match[0][1]
}

module_var_uses contains u if {
	some c in constrained
	name := module_var_name(c.r, c.value)
	u := object.union(c, {"name": name, "dir": file_dir(c.r.path)})
}

variable_decls(dir, name) := [b |
	some f in input
	file_dir(f.path) == dir
	some b in object.get(object.get(f.contents, "variable", {}), name, [])
]

deny contains msg if {
	some u in module_var_uses
	count(variable_decls(u.dir, u.name)) == 0
	msg := sprintf("%s: %s = var.%s, but %s declares no variable \"%s\"", [label(u.r), u.arg, u.name, u.dir, u.name])
}

deny contains msg if {
	some u in module_var_uses
	some b in variable_decls(u.dir, u.name)
	not "default" in object.keys(b)
	msg := sprintf("%s: %s = var.%s needs a literal default in %s (a variable with no default can't be checked)", [label(u.r), u.arg, u.name, u.dir])
}

deny contains msg if {
	some u in module_var_uses
	some b in variable_decls(u.dir, u.name)
	d := b["default"]
	not limit_ok(u.kind, d, u.r.path)
	msg := sprintf("%s: %s = var.%s, whose default %v fails %s", [label(u.r), u.arg, u.name, d, limit_text(u.kind, u.r.path)])
}

deny contains msg if {
	some u in module_var_uses
	some m in modules
	module_target(m) == u.dir
	u.name in object.keys(m.body)
	v := m.body[u.name]
	not limit_ok(u.kind, v, m.path)
	msg := sprintf("%s: module.%s passes %s = %v to %s (%s), which fails %s (must be a literal that passes)", [m.path, m.name, u.name, v, u.dir, u.arg, limit_text(u.kind, m.path)])
}

deny contains msg if {
	some u in module_var_uses
	some m in modules
	module_target(m) == u.dir
	not u.name in object.keys(m.body)
	some b in variable_decls(u.dir, u.name)
	d := b["default"]
	not limit_ok(u.kind, d, m.path)
	msg := sprintf("%s: module.%s omits %s, so %s's default %v applies, which fails %s", [m.path, m.name, u.name, u.dir, d, limit_text(u.kind, m.path)])
}
