#!/usr/bin/env bash
# check-dependabot-majors.sh — ecofolk-infra#70: every `terraform` ecosystem entry in dependabot.yml must
# ignore semver-MAJOR updates for all dependencies (dependency-name '*', update-types containing
# version-update:semver-major), so a provider major never arrives as an auto-PR (Dependabot PR #68 proposed
# google 5 -> 8 in one jump with no plan visible). Minor and patch are not ignored. Other ecosystems
# (github-actions) are not constrained here.
# Coverage (Architect, #124): every directory under the repo root that holds a versions.tf must be listed in
# a terraform entry's `directories:` / `directory:` (a `*` glob entry counts), so a new module cannot sit
# outside Dependabot's view. The root is the second argument, or the grandparent of a file named
# .github/dependabot.yml; for any other file with no root given, coverage is not checked.
# Usage: check-dependabot-majors.sh [dependabot.yml [repo-root]]   (default .github/dependabot.yml)
# Exit: 0 ok; 1 a terraform entry lacks the ignore, or a versions.tf directory is unlisted (names
# file:entry / the directory); 2 the file is missing, unparseable or has no terraform entry at all (a guard
# that finds nothing to check fails rather than passing).
# Surface path (CODEOWNERS): weakening this needs ARCHITECT APPROVED.
set -euo pipefail

file="${1:-.github/dependabot.yml}"
[ -f "$file" ] || { echo "check-dependabot-majors: $file not found" >&2; exit 2; }
python3 -I -c 'import yaml' 2>/dev/null || { echo "check-dependabot-majors: python3 with PyYAML is required" >&2; exit 2; }

python3 -I - "$file" "${2:-}" <<'PY'
import fnmatch
import os
import sys
import yaml

path = sys.argv[1]
root = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
if root is None and os.path.basename(os.path.dirname(os.path.abspath(path))) == ".github":
    root = os.path.dirname(os.path.dirname(os.path.abspath(path)))
try:
    doc = yaml.safe_load(open(path))
except Exception as exc:  # unparseable: fail closed
    print(f"check-dependabot-majors: {path} does not parse: {exc}", file=sys.stderr)
    sys.exit(2)
updates = doc.get("updates") if isinstance(doc, dict) else None
if not isinstance(updates, list):
    print(f"check-dependabot-majors: {path} has no updates list", file=sys.stderr)
    sys.exit(2)
tf = [(i, u) for i, u in enumerate(updates) if isinstance(u, dict) and u.get("package-ecosystem") == "terraform"]
if not tf:
    print(f"check-dependabot-majors: {path} has no terraform ecosystem entry to check", file=sys.stderr)
    sys.exit(2)
bad = 0
for i, u in tf:
    ok = any(
        isinstance(r, dict)
        and r.get("dependency-name") == "*"
        and "version-update:semver-major" in (r.get("update-types") or [])
        for r in (u.get("ignore") or [])
    )
    if not ok:
        print(
            f"{path}: updates[{i}] (terraform) does not ignore semver-major for dependency-name '*' "
            "(ecofolk-infra#70: provider majors are taken by hand, one per PR, behind a plan-only proof)"
        )
        bad = 1

covered = 0
if root:
    listed = set()
    for _, u in tf:
        d = u.get("directories") or []
        listed.update(d if isinstance(d, list) else [d])
        if u.get("directory"):
            listed.add(u["directory"])
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [n for n in dirnames if n not in (".git", ".terraform")]
        if "versions.tf" not in filenames:
            continue
        rel = "/" + os.path.relpath(dirpath, root).replace(os.sep, "/")
        rel = "/" if rel == "/." else rel
        covered += 1
        if not any(rel == p or ("*" in p and fnmatch.fnmatchcase(rel, p)) for p in listed):
            print(
                f"{path}: {rel} holds a versions.tf but is not in any terraform entry's directories "
                "(add it so Dependabot watches it, ecofolk-infra#70)"
            )
            bad = 1
if bad:
    sys.exit(1)
cov = f"; {covered} versions.tf dir(s) all listed" if root else ""
print(f"check-dependabot-majors: ok ({len(tf)} terraform entr{'y' if len(tf) == 1 else 'ies'} ignore semver-major{cov})")
PY
