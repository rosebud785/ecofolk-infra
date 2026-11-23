# check-plan-tree.jq — the rules of check-plan-tree.sh, judged on hcl2json's PARSED output (ecofolk-infra#162, Architect
# ruling c7086246324 after ef-qa's HOLD c7086176386). A line scan cannot be right about HCL: Terraform accepts unquoted
# labels (`provider google {`), a leading `/* … */` on a line, and more. Every rule here reads the parse tree, so a form
# Terraform accepts cannot hide from it. hcl2json (hcl/v2, the parser Terraform uses) normalises all of that away.
#
# Called as:
#   jq -r --arg mode tf|lock --arg kind root|env|module|other --argjson allow '["hashicorp/google", …]' -f check-plan-tree.jq <json>
#     mode lock  a .terraform.lock.hcl: every provider in it must be on the allowlist
#     mode tf    a .tf file; `kind` says where it lives: root (the planned root module, environments/dev), env (another
#                environments/* root), module (modules/**), other (anywhere else)
# Output: one tab-separated line per finding, no output = clean:
#   ERR<TAB>message          a refusal
#   MODSRC<TAB>path          a local module source, for the caller to resolve inside the tree
#   BACKEND<TAB>gcs          one `backend "gcs"` declared in a root-kind file (the caller counts them: exactly one)
#
# hcl2json's shape (read from a CI run, committed under scripts/tests/hcl/): a block with labels is
# `{type: {name: [ {attrs…} ]}}`, a block with one label is `{label: [ {…} ]}`, an unlabelled block is `[ {…} ]`, an
# attribute map is an object, a literal string is a string and an expression is `"${…}"`.

def scalar: type == "string" or type == "number" or type == "boolean";
def objs: if type == "array" then .[] | objects elif type == "object" then . else empty end;
def names: $allow | map(split("/")[1]);
def providerok($p): ($p | sub("^registry\\.terraform\\.io/"; "")) as $s | ($allow | index($s)) != null;
def err($m): "ERR\t" + $m;

# every object at any depth (a nested block or a map), to find a key wherever it hides
def everywhere: .. | objects;

# (F3, ef-qa c7089806892) Terraform loads `data` / `resource` blocks NOT ONLY at the top level: a `data` block scoped
# inside a `check "…" {}` block is read during PLAN (and an `ephemeral` block is a block of the same two-label shape). A
# rule that reads only the top-level keys never judges a nested one. So the judge looks at EVERY depth for a key named
# data / resource / ephemeral / action whose value has the two-label block shape `{type: {name: [ {…} ]}}`, and judges
# its types. Fail closed: a block of that shape is judged wherever it hides. A provider-schema attribute that merely
# shares the name (`data = { a = "b" }`, or `data { … }` with no labels) has a different shape and is not a block map.
def blockmap: type == "object" and length > 0
  and all(.[]; type == "object" and length > 0 and all(.[]; type == "array" and length > 0 and all(.[]; type == "object")));
def declared($kind): [everywhere | select(has($kind)) | .[$kind] | select(blockmap) | keys[]] | unique;

if $mode == "lock" then
  ((.provider // {}) | keys[] | select(providerok(.) | not) | err("lockfile provider \"" + . + "\" is not in the allowlist"))
else
  # 0. (Architect, infra#162 c7089836077) the TOP-LEVEL block kinds are an ALLOWLIST, so a kind Terraform adds later (or one
  # that can nest a data block: `check`, `ephemeral`, `action`) is refused by name instead of being understood: simpler,
  # and fail closed. Everything an EcoFolk root or module uses today is in the list.
  (keys[] | select(IN("terraform", "provider", "variable", "locals", "output", "module", "resource", "data", "moved", "import", "removed") | not)
     | err("top-level block \"" + . + "\" is not accepted in a PR-time plan (allowed kinds: terraform, provider, variable, locals, output, module, resource, data, moved, import, removed)")),
  # 1. data sources that run a program or a request at plan time (named, for the clearest message)
  (declared("data")[] | select(. == "external" or . == "http") | err("data \"" + . + "\" runs code or a request at plan time")),
  # 3. (R6) resource and data TYPES are an ALLOWLIST: a type must start with the prefix of an allowlisted provider
  # (google_ for google and google-beta, archive_ for archive: the provider's name before any hyphen, plus "_"). A
  # denylist of dangerous names missed the BUILT-IN `terraform_remote_state`, whose backend and config are plain HCL (a
  # plan-time request to any host carrying interpolated file() content: the runner's credential file). Everything not
  # on the list is refused by name: terraform_remote_state, terraform_data, random_*, external_*, http_*, local_*, null_*…
  # The kinds judged: resource and data, wherever they are nested (belt and braces behind rule 0: a block map of this shape
  # anywhere is judged, so even a nesting rule 0 does not know about cannot hide one).
  ((declared("resource")[]), (declared("data")[]) | . as $type
     | ($allow | map(split("/")[1] | sub("-.*$"; "") + "_") | unique) as $prefixes
     | select(any($prefixes[]; . as $p | $type | startswith($p)) | not)
     | err("\"" + $type + "\" belongs to a provider that is not accepted in a PR-time plan (resource and data types must start with: " + ($prefixes | join(", ")) + ")")),
  # 2. providers: only the allowlisted ones, and the google ones take an ATTRIBUTE allowlist (R5)
  ((.provider // {}) | to_entries[] | .key as $name | .value as $cfgs
     | (if ($name | IN("external", "http", "local", "null")) then err("provider \"" + $name + "\" is not accepted in a PR-time plan")
        elif ($name | IN(names[])) | not then err("provider \"" + $name + "\" is not on the allowlist")
        else empty end),
       ($cfgs | objs
         | if ($name == "google" or $name == "google-beta") then
             ( to_entries[]
               | select((.key | IN("project", "region", "zone", "alias", "default_labels")) | not)
               | err("provider \"" + $name + "\" attribute or block \"" + .key + "\" is not on the google provider's allowlist (project, region, zone, alias, default_labels)")),
             ( to_entries[]
               | select(.key | IN("project", "region", "zone", "alias"))
               | select((.value | scalar) | not)
               | err("provider \"" + $name + "\" attribute \"" + .key + "\" must be a plain value")),
             ( select(has("default_labels")) | .default_labels
               | select((type == "object" and (to_entries | all(.value | scalar))) | not)
               | err("provider \"" + $name + "\" default_labels must be a map of plain key = value"))
           else
             ( to_entries[] | err("provider \"" + $name + "\" takes no attributes here: \"" + .key + "\""))
           end)),
  # 4. provisioner blocks anywhere
  (select([everywhere | select(has("provisioner"))] | length > 0) | err("provisioner blocks are not accepted in a PR-time plan")),
  # 5. module sources: only a local path (the caller checks it stays inside the tree)
  ((.module // {}) | to_entries[] | .key as $m | .value | objs
     | (.source) as $s
     | if ($s | type) != "string" then err("module \"" + $m + "\" has no literal source")
       elif ($s | test("^\\.\\.?/")) and ($s | contains("${") | not) then "MODSRC\t" + $s
       else err("module \"" + $m + "\" source \"" + $s + "\" is not a local path")
       end),
  # 6. the providers a root asks for
  ((.terraform // []) | objs | (.required_providers // []) | objs | to_entries[]
     | (if (.value | type) == "string" then "hashicorp/" + .key
        elif ((.value | type) == "object") and ((.value.source // null) | type) == "string" then .value.source
        else "hashicorp/" + .key end) as $src
     | select(providerok($src) | not)
     | err("provider source \"" + $src + "\" is not on the allowlist")),
  # 7. archive_file WRITES a file at plan time, wherever output_path says (R1): exactly one shape is accepted
  (everywhere | select(has("output_path")) | .output_path
     | select(((type == "string") and test("^\\$\\{path\\.(root|module)\\}/\\.terraform/tmp/[A-Za-z0-9][A-Za-z0-9._-]*$")) | not)
     | err("output_path must be \"${path.root}/.terraform/tmp/<file>\" (an archive is WRITTEN at plan time): "
           + ((tostring | gsub("`"; "") | .[0:120])))),
  # 8. the backend (R2): the PR must not choose where state is read, or where the token goes
  ((.terraform // []) | objs
     | ((select(has("cloud")) | err("a cloud block is not accepted (the PR would choose the backend)")),
        ((.backend // {}) | to_entries[] | .key as $t | .value as $bodies
           | (if $t != "gcs" then err("backend \"" + $t + "\" is not accepted (only gcs, in a root module)")
              elif $kind == "module" then err("a backend block in a module is not accepted")
              else empty end),
             (if $t == "gcs" and $kind == "root" then ($bodies | objs | "BACKEND\tgcs") else empty end),
             (if $t == "gcs" and $kind == "root" then
                ($bodies | objs | to_entries[]
                  | select((.key == "prefix" and (.value | type) == "string" and (.value | test("^[A-Za-z0-9._/-]+$"))) | not)
                  | err("the gcs backend may set only prefix = \"<literal>\" (the bucket is the workflow's): " + (.key | gsub("`"; "") | .[0:60])))
              else empty end)))),
  # 10. any endpoint override, anywhere
  (everywhere | keys[] | select(test("_custom_endpoint$")) | err("a *_custom_endpoint attribute would send the access token to another host"))
end
