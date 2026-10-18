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

A file that does not parse FAILS the guard: an unreadable workflow is not a clean one.

Rule 3 lives here too: in an UNTRUSTED workflow, ANY `secrets` identifier inside a `${{ }}` expression fails.

Usage: check-workflow-permissions.py <allowlist,comma-separated> <file>...
       check-workflow-permissions.py --trigger <file>   # prints `trusted` or the untrusted trigger name
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
SECRETS_IDENT = re.compile(r"\bsecrets\b")


def secrets_in_expressions(text: str) -> list[int]:
    """Line numbers of every `${{ }}` expression (comments stripped, line numbers kept) that contains the
    identifier `secrets`, in any spelling: dot, bracket, toJson(secrets), format('{0}', secrets.X), any
    function. No list of spellings (#79): one identifier test. `secrets.GITHUB_TOKEN` is included on purpose;
    a token need is spelled `github.token`."""
    stripped = re.sub(r"(^|[ \t])#.*$", r"\1", text, flags=re.MULTILINE)
    return [
        stripped.count("\n", 0, m.start()) + 1
        for m in EXPRESSION.finditer(stripped)
        if SECRETS_IDENT.search(m.group(0))
    ]


REF_GUARD = re.compile(r"github\.ref\s*==\s*['\"]refs/heads/main['\"]")
SECRET_USE = re.compile(r"\$\{\{[^}]*\bsecrets\b(?!\.GITHUB_TOKEN\b)")


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


def _guarded(job: object) -> bool:
    """True only for the exact good shape of a job-level `if:` (allowlist, so it fails closed): the main-ref
    guard alone, or the guard followed by `&& <term>`..., after stripping `${{ }}`. The condition may contain no
    `!`, `||` or parentheses, so a negation (`!(…)`, `!=`) or an OR can never read as a guard. Deliberate
    fail-closed side effect: `… == 'refs/heads/main' && !cancelled()` is rejected (#78, Architect)."""
    cond = job.get("if") if isinstance(job, dict) else None
    if not isinstance(cond, str):
        return False
    text = re.sub(r"^\s*\$\{\{|\}\}\s*$", "", cond.strip()).strip()
    if re.search(r"[!()]|\|\|", text):
        return False
    first, *rest = [part.strip() for part in text.split("&&")]
    return bool(REF_GUARD.fullmatch(first)) and all(rest)


def _unguarded_privileged_dispatch_job(root, loader, text: str) -> str | None:
    """Name of the first job that holds write / id-token / secrets without a refs/heads/main guard, else None.
    Only asked when the workflow has workflow_dispatch, which can be run against ANY ref (#78)."""
    wf_perms = None
    for _, v in find(root, loader, "permissions"):
        wf_perms = loader.construct_object(v, deep=True)
    jobs_nodes = [v for _, v in find(root, loader, "jobs")]
    outside = text
    for jn in jobs_nodes:
        outside = text[: jn.start_mark.index] + text[jn.end_mark.index :]
    outside_secret = bool(SECRET_USE.search(outside))
    for jn in jobs_nodes:
        for jk, job in mapping_items(jn, loader):
            jobval = loader.construct_object(job, deep=True)
            perms = jobval.get("permissions", wf_perms) if isinstance(jobval, dict) else wf_perms
            writes = perms == "write-all" or (isinstance(perms, dict) and "write" in perms.values())
            # A job-level `secrets:` (inherit, or a mapping) hands secrets to a reusable workflow whose body this
            # file cannot show, so it counts as secret use whatever the value is.
            inherits = isinstance(jobval, dict) and bool(jobval.get("secrets"))
            uses_secret = (
                outside_secret or inherits or bool(SECRET_USE.search(text[job.start_mark.index : job.end_mark.index]))
            )
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
                        return f"workflow_dispatch (job {bad} is privileged without an `if: github.ref == 'refs/heads/main'` guard)"
    return None if found else "<no on:>"


def check_permissions(node, loader, line, where, on_pr: str | None, allowed, report):
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
                for n in secrets_in_expressions(text):
                    report(
                        n,
                        f"secrets.* referenced in a workflow triggered by {on_pr}"
                        " (`secrets` inside ${{ }}; use github.token)",
                    )
            if on_pr and on_pr.startswith("workflow_dispatch ("):
                # A privileged dispatch job without the main guard fails on its own: it may hold secrets only
                # through `secrets:` (inherit/mapping), which neither the permissions rule nor the grep can see.
                report(1, f"workflow triggered by {on_pr}")
            is_allowed = os.path.basename(path) in allow
            for k, v in find(root, loader, "permissions"):
                check_permissions(v, loader, k.start_mark.line + 1, "workflow level", on_pr, is_allowed, report)
            for _, jobs in find(root, loader, "jobs"):
                for jk, job in mapping_items(jobs, loader):
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


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "--trigger":
        print(trigger_of(argv[1]))
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
