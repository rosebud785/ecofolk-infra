#!/usr/bin/env python3
"""Permission rules of the E4 workflow guard (ecofolk-infra#31). Called by check-workflows.sh; run with -I.

Each workflow is PARSED with a safe YAML loader, so anchors, aliases, merge keys, flow-style mappings and
quoted keys are resolved the way GitHub Actions resolves them. A line regex cannot see `id-token: *p`.
The resolved `permissions` is checked at the workflow level and at every job:

  * `write-all` is forbidden anywhere (it grants id-token: write and write on everything);
  * `id-token` == write is allowed only in a JOB's permissions, in an allowlisted file, not PR-triggered;
    at workflow level it fails even in an allowlisted file;
  * in an UNTRUSTED workflow (any trigger outside push-to-main / schedule / guarded workflow_dispatch, unknown
    triggers and an unreadable `on:` included; see untrusted_trigger), every permission value must be `read` or `none`.

  * in an UNTRUSTED workflow, a job with no `permissions` of its own in a workflow with none at the top level
    FAILS: with no block the job gets the repo/org default token, which can be write-all (#65);
  * a DUPLICATE key inside any `permissions` mapping fails: YAML keeps the last one, so an earlier grant
    could be hidden or a later one overridden unseen (#65, Architect's review of #63).

A file that does not parse FAILS the guard: an unreadable workflow is not a clean one.

Rule 3 lives here too: in an UNTRUSTED workflow, ANY `secrets` identifier inside a `${{ }}` expression fails.

Usage: check-workflow-permissions.py <allowlist,comma-separated> <file>...
       check-workflow-permissions.py --trigger <file>   # prints `trusted` or the untrusted trigger name
       check-workflow-permissions.py --tf-target <file>   # prints `dev` or `unsafe` (check-workflows.sh rule 5)
       check-workflow-permissions.py --tf-lines <file>    # line numbers of plan/apply-capable lines (rule 5)
Prints `file:line: message` per violation (line = the offending `permissions:` key); exit 1 if any.
Surface path (CODEOWNERS): weakening this needs ARCHITECT APPROVED.
"""

from __future__ import annotations

import os
import re
import sys

import yaml


def key_name(node: yaml.Node) -> object:
    return node.value if isinstance(node, yaml.ScalarNode) else None


def mapping_items(node: yaml.Node, loader: yaml.SafeLoader) -> list[tuple[yaml.Node, yaml.Node]]:
    """Key/value node pairs of a mapping with merge keys (`<<`) flattened, as the loader constructs it."""
    if not isinstance(node, yaml.MappingNode):
        return []
    loader.flatten_mapping(node)
    return list(node.value)


def find(node: yaml.Node, loader: yaml.SafeLoader, name: str) -> list[tuple[yaml.Node, yaml.Node]]:
    return [(k, v) for k, v in mapping_items(node, loader) if key_name(k) == name]


# Trusted triggers (Architect, ecofolk-infra#31): in this repo these run from a protected branch's copy of the
# workflow, not a contributor's. EVERYTHING else is untrusted, unknown and future triggers included (an allowlist
# fails closed; a list of "PR-ish" triggers already missed two). A workflow is untrusted if ANY trigger is outside
# the set. check-workflows.sh asks this same function (via --trigger) for rule 3, so there is one definition.
TRUSTED_TRIGGERS = frozenset({"push", "schedule", "workflow_dispatch"})


EXPRESSION = re.compile(r"\$\{\{.*?\}\}", re.DOTALL)
# Expression contexts are case-insensitive in GitHub Actions (`Secrets.K` reads the secrets context), so every
# identifier match here is IGNORECASE and fails closed.
SECRETS_IDENT = re.compile(r"\bsecrets\b", re.IGNORECASE)


def scalar_nodes(node: yaml.Node, skip_keys: tuple[str, ...] = ()) -> list[yaml.ScalarNode]:
    """Every scalar node (keys and values) under `node`, aliases resolved, each node once. A `#` inside a quoted
    or block scalar is CONTENT that GitHub evaluates, so detection reads the parsed scalars, never the raw text:
    only real YAML comments (which the parser drops) are ignored. `skip_keys` prunes those mapping keys' values."""
    out: list[yaml.ScalarNode] = []
    seen: set[int] = set()

    def walk(n: yaml.Node) -> None:
        if id(n) in seen:
            return
        seen.add(id(n))
        if isinstance(n, yaml.ScalarNode):
            out.append(n)
        elif isinstance(n, yaml.SequenceNode):
            for c in n.value:
                walk(c)
        elif isinstance(n, yaml.MappingNode):
            for k, v in n.value:
                walk(k)
                if not (isinstance(k, yaml.ScalarNode) and k.value in skip_keys):
                    walk(v)

    walk(node)
    return out


def secrets_in_expressions(root: yaml.Node) -> list[int]:
    """Line numbers of every scalar holding a `${{ }}` expression that contains the identifier `secrets`, in any
    spelling: dot, bracket, toJson(secrets), format('{0}', secrets.X), any function. No list of spellings (#79):
    one identifier test over the parsed scalars. `secrets.GITHUB_TOKEN` is included on purpose; a token need
    is spelled `github.token`."""
    lines = []
    for sc in scalar_nodes(root):
        for m in EXPRESSION.finditer(sc.value):
            if SECRETS_IDENT.search(m.group(0)):
                lines.append(sc.start_mark.line + 1 + sc.value.count("\n", 0, m.start()))
    return lines


REF_GUARD = re.compile(r"github\.ref\s*==\s*['\"]refs/heads/main['\"]")
SECRET_USE = re.compile(r"\$\{\{[^}]*\bsecrets\b(?!\.GITHUB_TOKEN\b)", re.IGNORECASE)


def _has_secret_use(node: yaml.Node, skip_keys: tuple[str, ...] = ()) -> bool:
    return any(SECRET_USE.search(sc.value) for sc in scalar_nodes(node, skip_keys))


def _push_is_main_only(value: object) -> bool:
    """`push` is trusted only when limited to the main branch: `branches: [main]` (or `main`), with no
    branches-ignore, tags or tags-ignore. An unmerged branch's push runs THAT branch's copy of the workflow
    (#78), so a bare push, a wildcard or another branch is untrusted."""
    if not isinstance(value, dict):
        return False
    if any(k in value for k in ("branches-ignore", "tags", "tags-ignore")):
        return False
    branches = value.get("branches")
    if isinstance(branches, str):
        branches = [branches]
    return branches == ["main"]


# GitHub's `==` (and contains/startsWith) compare strings CASE-INSENSITIVELY, so `github.ref ==
# 'refs/heads/main'` is also true on a branch named `Main` or `MAIN` (#82). `github.ref_protected` is true only
# when a branch protection rule matched the ref, and those patterns are case-sensitive, so it is the case-exact
# half of the guard: an unprotected `Main` branch can't satisfy it.
PROTECTED_TERM = re.compile(r"github\.ref_protected(\s*==\s*true)?")


def _guarded(job: object) -> bool:
    """True only for the exact good shape of a job-level `if:` (allowlist, so it fails closed): the main-ref
    guard followed by `&& github.ref_protected` (case-exact, #82) and optionally more `&& <term>`..., after
    stripping `${{ }}`. The condition may contain no
    `!`, `||` or parentheses, so a negation (`!(…)`, `!=`) or an OR can never read as a guard. Deliberate
    fail-closed side effect: `… == 'refs/heads/main' && !cancelled()` is rejected (#78, Architect)."""
    cond = job.get("if") if isinstance(job, dict) else None
    if not isinstance(cond, str):
        return False
    text = re.sub(r"^\s*\$\{\{|\}\}\s*$", "", cond.strip()).strip()
    if re.search(r"[!()]|\|\|", text):
        return False
    first, *rest = [part.strip() for part in text.split("&&")]
    return (
        bool(REF_GUARD.fullmatch(first))
        and all(rest)
        and any(PROTECTED_TERM.fullmatch(term) for term in rest)
    )


def _unguarded_privileged_dispatch_job(root, loader, text: str) -> str | None:
    """Name of the first job that holds write / id-token / secrets without a refs/heads/main guard, else None.
    Only asked when the workflow has workflow_dispatch, which can be run against ANY ref (#78)."""
    wf_perms = None
    for _, v in find(root, loader, "permissions"):
        wf_perms = loader.construct_object(v, deep=True)
    jobs_nodes = [v for _, v in find(root, loader, "jobs")]
    outside_secret = _has_secret_use(root, skip_keys=("jobs",))
    for jn in jobs_nodes:
        for jk, job in mapping_items(jn, loader):
            jobval = loader.construct_object(job, deep=True)
            perms = jobval.get("permissions", wf_perms) if isinstance(jobval, dict) else wf_perms
            writes = perms == "write-all" or (isinstance(perms, dict) and "write" in perms.values())
            # A job-level `secrets:` (inherit, or a mapping) hands secrets to a reusable workflow whose body this
            # file cannot show, so it counts as secret use whatever the value is.
            inherits = isinstance(jobval, dict) and bool(jobval.get("secrets"))
            uses_secret = outside_secret or inherits or _has_secret_use(job)
            if (writes or uses_secret) and not _guarded(jobval):
                return str(key_name(jk))
    return None


def untrusted_trigger(root: yaml.Node, loader: yaml.SafeLoader, text: str = "") -> str | None:
    """Name of the first untrusted trigger, or a description if `on:` is missing or unreadable; None when every
    trigger is trusted. Trusted = push limited to main, schedule, and workflow_dispatch whose privileged jobs
    carry a refs/heads/main guard."""
    found = False
    for key in ("on", "true", "True"):  # YAML 1.1 reads a bare `on` key as boolean true
        for _, v in find(root, loader, key):
            found = True
            on = loader.construct_object(v, deep=True)
            if isinstance(on, str):
                names, cfg = [on], {}
            elif isinstance(on, list):
                names, cfg = list(on), {}
            elif isinstance(on, dict):
                names, cfg = list(on), on
            else:
                return "<unreadable on:>"
            if not names:
                return "<empty on:>"
            for t in names:
                if not isinstance(t, str):
                    return f"<unreadable trigger {t!r}>"
                if t not in TRUSTED_TRIGGERS:
                    return t
                if t == "push" and not _push_is_main_only(cfg.get("push")):
                    return "push (not limited to branches: [main])"
                if t == "workflow_dispatch":
                    bad = _unguarded_privileged_dispatch_job(root, loader, text)
                    if bad:
                        return f"workflow_dispatch (job {bad} is privileged without an `if: github.ref == 'refs/heads/main' && github.ref_protected` guard)"
    return None if found else "<no on:>"


def check_permissions(node, loader, line, where, on_pr: str | None, allowed, report):
    if isinstance(node, yaml.MappingNode):
        loader.flatten_mapping(node)  # merge keys expanded, so a merged-then-redeclared key shows as a duplicate
        names = [key_name(k) for k, _ in node.value]
        for name in sorted({n for n in names if names.count(n) > 1}, key=str):
            report(line, f"duplicate key {name!r} in permissions at {where} (YAML keeps the last; fails the guard)")
    perms = loader.construct_object(node, deep=True)
    if perms == "write-all":
        report(line, f"permissions: write-all at {where} (grants id-token: write and write on everything)")
        return
    if not isinstance(perms, dict):
        return
    for scope, value in perms.items():
        if scope == "id-token" and value == "write":
            if where == "workflow level":
                report(line, "id-token: write at workflow level (job-level only, on the apply job)")
            # the pre-#31 reasons stay reported alongside, so each fixture keeps failing for its own reason
            if on_pr:
                report(line, f"id-token: write in a workflow triggered by {on_pr}")
            elif not allowed:
                report(line, "id-token: write outside the allowlist")
        elif on_pr and value not in ("read", "none"):
            report(line, f"permissions {scope}: {value} at {where} in a workflow triggered by {on_pr} (read or none only)")


def check_file(path: str, allow: set[str]) -> list[str]:
    out: list[str] = []

    def report(line: int, msg: str) -> None:
        out.append(f"{path}:{line}: {msg}")

    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        loader = yaml.SafeLoader(text)
        try:
            root = loader.get_single_node()
            if root is None or not isinstance(root, yaml.MappingNode):
                report(1, "workflow is not a YAML mapping (parse failure fails the guard)")
                return out
            on_pr = untrusted_trigger(root, loader, text)
            if on_pr:
                for n in secrets_in_expressions(root):
                    report(
                        n,
                        f"secrets.* referenced in a workflow triggered by {on_pr}"
                        " (`secrets` inside ${{ }}; use github.token)",
                    )
            if on_pr:
                # A job-level `secrets:` key (inherit or a mapping) in an untrusted workflow, read from the parsed
                # YAML so a `#` in a string cannot hide it.
                for _, jobs in find(root, loader, "jobs"):
                    for jk, job in mapping_items(jobs, loader):
                        for k, v in find(job, loader, "secrets"):
                            if loader.construct_object(v, deep=True):
                                report(
                                    k.start_mark.line + 1,
                                    f"secrets: passed to job {key_name(jk)} in a workflow triggered by {on_pr}",
                                )
            if on_pr and on_pr.startswith("workflow_dispatch ("):
                # A privileged dispatch job without the main guard fails on its own: it may hold secrets only
                # through `secrets:` (inherit/mapping), which neither the permissions rule nor the grep can see.
                report(1, f"workflow triggered by {on_pr}")
            is_allowed = os.path.basename(path) in allow
            wf_perms = find(root, loader, "permissions")
            for k, v in wf_perms:
                check_permissions(v, loader, k.start_mark.line + 1, "workflow level", on_pr, is_allowed, report)
            for _, jobs in find(root, loader, "jobs"):
                for jk, job in mapping_items(jobs, loader):
                    if on_pr and not wf_perms and not find(job, loader, "permissions"):
                        report(
                            jk.start_mark.line + 1,
                            f"job {key_name(jk)} has no permissions: block (and the workflow has none) in a workflow"
                            f" triggered by {on_pr}; it would get the repo default token. Add `permissions:"
                            " contents: read` (or `{}`)",
                        )
                    for k, v in find(job, loader, "permissions"):
                        check_permissions(
                            v, loader, k.start_mark.line + 1, f"job {key_name(jk)}", on_pr, is_allowed, report
                        )
        finally:
            loader.dispose()
    except (yaml.YAMLError, OSError, UnicodeDecodeError, RecursionError) as e:
        report(1, f"YAML parse failure fails the guard: {str(e).splitlines()[0] if str(e) else type(e).__name__}")
    return out


def trigger_of(path: str) -> str:
    """`trusted`, or the name of the untrusted trigger. A file that does not parse is untrusted."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        loader = yaml.SafeLoader(text)
        try:
            root = loader.get_single_node()
            if root is None or not isinstance(root, yaml.MappingNode):
                return "<unparseable workflow>"
            return untrusted_trigger(root, loader, text) or "trusted"
        finally:
            loader.dispose()
    except (yaml.YAMLError, OSError, UnicodeDecodeError, RecursionError):
        return "<unparseable workflow>"


# ---- Rule 5 of check-workflows.sh (#88): plan/apply only against a PROVEN environments/dev target. ----
# Positive proof, per plan/apply-capable segment, never a denylist of prod spellings. See check-workflows.sh.
ENV_OCC = re.compile(r"environments/")
ENV_DEV = re.compile(r"environments/dev(?=$|[/\"'\s])")
ON_KEYS = ("on", "true", "True")
PATH_FILTERS = ("paths", "paths-ignore")  # on.<event>.paths filters pick which pushes run; not a target
# A `terraform`/`tofu` word with plan or apply after it, in one (de-quoted) segment.
TF_PLAN = re.compile(r"(^|[^A-Za-z0-9_-])(terraform|tofu|terragrunt)([^A-Za-z0-9_-].*)?[\s](plan|apply)([^A-Za-z0-9_-]|$)")
ACTION_PLAN = re.compile(r"(plan|apply)", re.IGNORECASE)
SEGMENT_SPLIT = re.compile(r"\n|;|&|\|\||\||\$\(|<\(|>\(|`")  # `&` covers && and a lone background &
ASSIGNMENTS = re.compile(r"^\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*")
LEAD_OPENERS = re.compile(r"^\s*(?:(?:[{(]|then|do|else)(?:\s+|$))*")
TEXT_START = re.compile(r"^(?:echo|printf|:)(?![A-Za-z0-9_-])")
CHDIR = re.compile(r"-chdir=((?:\$\{\{.*?\}\}|\S)+)")
ENV_REF = re.compile(r"\$\{\{\s*env\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}|\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)")
# [<prefix>/]environments/dev, then end or `/`. A prefix is a fixed relative path: no `..`, no expression.
DEV_TARGET = re.compile(r"^(?:[A-Za-z0-9_][A-Za-z0-9_.-]*/)*environments/dev(?:/[A-Za-z0-9_./-]*)?$")


def _mapping_get(node: yaml.Node | None, loader: yaml.SafeLoader, name: str) -> yaml.Node | None:
    if node is None:
        return None
    hits = find(node, loader, name)
    return hits[0][1] if hits else None


def _literal_env(node: yaml.Node | None, loader: yaml.SafeLoader) -> dict[str, str]:
    """`env:` entries whose value is a literal scalar (no `$`, so no expression and no expansion)."""
    env = _mapping_get(node, loader, "env")
    out: dict[str, str] = {}
    if isinstance(env, yaml.MappingNode):
        for k, v in mapping_items(env, loader):
            if isinstance(k, yaml.ScalarNode) and isinstance(v, yaml.ScalarNode) and "$" not in v.value:
                out[k.value] = v.value
    return out


def _default_wd(node: yaml.Node | None, loader: yaml.SafeLoader) -> str | None:
    d = _mapping_get(_mapping_get(_mapping_get(node, loader, "defaults"), loader, "run"), loader, "working-directory")
    return d.value if isinstance(d, yaml.ScalarNode) else None


def _target_ok(source: str | None, envs: list[dict[str, str]]) -> bool:
    """Does the directory source resolve to [<prefix>/]environments/dev? The ONLY indirection allowed is
    ${{ env.X }}, $X or ${X} with X a literal in an env map (nearest wins: step, job, workflow). Any other
    expression, an unresolved variable, or no source at all is unsafe."""
    if source is None:
        return False

    def sub(m: re.Match) -> str:
        name = m.group(1) or m.group(2) or m.group(3)
        for e in envs:
            if name in e:
                return e[name]
        return m.group(0)

    resolved = ENV_REF.sub(sub, source)
    if "$" in resolved or "{{" in resolved:
        return False
    return bool(DEV_TARGET.match(resolved))


def _segments(sc: yaml.ScalarNode) -> list[tuple[int, str]]:
    """(1-based line, segment) for each command segment of a scalar: `\\`-newline joined, shell quote
    characters removed, split on newline ; && || | $( and backticks. Shell comments are NOT stripped
    (over-detects, never misses)."""
    first = sc.start_mark.line + 1 + (1 if sc.style in ("|", ">") else 0)
    out: list[tuple[int, str]] = []
    raw = sc.value.split("\n")
    logical, start = "", None
    for i, ln in enumerate(raw):
        if start is None:
            start = i
        if ln.endswith("\\") and i < len(raw) - 1:
            logical += ln[:-1] + " "
            continue
        logical += ln
        for seg in SEGMENT_SPLIT.split(re.sub(r"[\"'\\]", "", logical)):
            out.append((first + start, seg))
        logical, start = "", None
    return out


def _capable(seg: str) -> bool:
    """A segment that can plan or apply: `terraform`/`tofu` ... plan|apply, unless the segment is TEXT: after
    leading VAR=value assignments it starts with echo, printf or `:`, or it is a whole-line comment (D')."""
    if not TF_PLAN.search(seg):
        return False
    if re.match(r"^\s*#", seg):
        return False
    # Grouping/compound-command openers (`{`, `(`, then, do, else) are skipped before the text test, so
    # `{ echo "terraform plan failed"; }` is text; `{ terraform apply; }` still starts with the command.
    rest = LEAD_OPENERS.sub("", seg)
    rest = rest[ASSIGNMENTS.match(rest).end():]
    return not TEXT_START.match(rest)


def tf_violations(path: str) -> list[int]:
    """Lines of plan/apply-capable segments whose target is not PROVEN dev, per step. [1] on a parse failure.
    A step's source is the segment's `-chdir=`, then the step's `working-directory`, then the job's, then the
    workflow's `defaults.run.working-directory`; none = unsafe. A job-level reusable-workflow call and a
    `uses:` action named plan/apply are capable too, and need the whole workflow to prove dev. Any non-dev
    `environments/` anywhere outside the path filters (the `on:` inputs included) makes every capable
    line unsafe."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        loader = yaml.SafeLoader(text)
        try:
            root = loader.get_single_node()
            if root is None or not isinstance(root, yaml.MappingNode):
                return [1]
            hits: set[int] = set()

            def on_scalars(v: yaml.Node, key: object) -> list[yaml.ScalarNode]:
                return scalar_nodes(v, PATH_FILTERS if key in ON_KEYS else ())

            all_scalars: list[yaml.ScalarNode] = []
            for k, v in mapping_items(root, loader):
                if isinstance(k, yaml.ScalarNode):
                    all_scalars.append(k)
                all_scalars.extend(on_scalars(v, key_name(k)))
            occ = [bool(ENV_DEV.match(s.value, m.start())) for s in all_scalars for m in ENV_OCC.finditer(s.value)]
            no_foreign_env = all(occ)  # every `environments/` is exactly environments/dev
            workflow_dev_only = no_foreign_env and bool(occ)

            wf_env = _literal_env(root, loader)
            wf_wd = _default_wd(root, loader)
            jobs = _mapping_get(root, loader, "jobs")

            def check_unit(scalars: list[yaml.ScalarNode], envs: list[dict[str, str]], wds: list[str | None]) -> None:
                source_wd = next((w for w in wds if w is not None), None)
                for sc in scalars:
                    for line, seg in _segments(sc):
                        if not _capable(seg):
                            continue
                        m = CHDIR.search(seg)
                        source = m.group(1) if m else source_wd
                        if not (no_foreign_env and _target_ok(source, envs)):
                            hits.add(line)

            if isinstance(jobs, yaml.MappingNode):
                for _, job in mapping_items(jobs, loader):
                    job_env, job_wd = _literal_env(job, loader), _default_wd(job, loader)
                    steps = _mapping_get(job, loader, "steps")
                    if isinstance(steps, yaml.SequenceNode):
                        for st in steps.value:
                            step_wd = _mapping_get(st, loader, "working-directory")
                            wds = [step_wd.value if isinstance(step_wd, yaml.ScalarNode) else None, job_wd, wf_wd]
                            check_unit(scalar_nodes(st), [_literal_env(st, loader), job_env, wf_env], wds)
                    check_unit(scalar_nodes(job, ("steps",)), [job_env, wf_env], [job_wd, wf_wd])
            skip = ("jobs",)
            rest = [s for k, v in mapping_items(root, loader) if key_name(k) not in skip for s in on_scalars(v, key_name(k))]
            check_unit(rest, [wf_env], [wf_wd])

            # Action named plan/apply, and job-level reusable-workflow calls: no directory source of their own,
            # so the whole workflow must prove dev (some environments/dev, and nothing else under environments/).
            for uses_v in _uses_values(root, loader):
                name = uses_v.value.split("@", 1)[0]
                if (ACTION_PLAN.search(name) or ".github/workflows/" in name) and not workflow_dev_only:
                    hits.add(uses_v.start_mark.line + 1)
            return sorted(hits)
        finally:
            loader.dispose()
    except (yaml.YAMLError, OSError, UnicodeDecodeError, RecursionError):
        return [1]


def _uses_values(node: yaml.Node, loader: yaml.SafeLoader) -> list[yaml.ScalarNode]:
    """Values of every `uses` key anywhere (step actions and job-level reusable-workflow calls)."""
    out: list[yaml.ScalarNode] = []
    seen: set[int] = set()

    def walk(n: yaml.Node) -> None:
        if id(n) in seen:
            return
        seen.add(id(n))
        if isinstance(n, yaml.SequenceNode):
            for c in n.value:
                walk(c)
        elif isinstance(n, yaml.MappingNode):
            for k, v in mapping_items(n, loader):
                if key_name(k) == "uses" and isinstance(v, yaml.ScalarNode):
                    out.append(v)
                else:
                    walk(v)

    walk(node)
    return out


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "--trigger":
        print(trigger_of(argv[1]))
        return 0
    if len(argv) == 2 and argv[0] == "--tf-violations":
        for n in tf_violations(argv[1]):
            print(n)
        return 0
    if len(argv) < 2:
        print("usage: check-workflow-permissions.py <allowlist,comma-separated> <file>...", file=sys.stderr)
        return 2
    allow = {a for a in argv[0].split(",") if a}
    problems = [line for f in argv[1:] for line in check_file(f, allow)]
    for line in problems:
        print(line)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
