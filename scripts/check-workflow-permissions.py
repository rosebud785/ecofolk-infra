#!/usr/bin/env python3
"""Permission rules of the E4 workflow guard (ecofolk-infra#31). Called by check-workflows.sh; run with -I.

Each workflow is PARSED with a safe YAML loader, so anchors, aliases, merge keys, flow-style mappings and
quoted keys are resolved the way GitHub Actions resolves them. A line regex cannot see `id-token: *p`.
The resolved `permissions` is checked at the workflow level and at every job:

  * `write-all` is forbidden anywhere (it grants id-token: write and write on everything);
  * `id-token` == write is allowed only in a JOB's permissions, in an allowlisted file, not PR-triggered;
    at workflow level it fails even in an allowlisted file;
  * in a pull_request-triggered workflow, every permission value must be `read` or `none`.

A file that does not parse FAILS the guard: an unreadable workflow is not a clean one.

Usage: check-workflow-permissions.py <allowlist,comma-separated> <file>...
Prints `file:line: message` per violation (line = the offending `permissions:` key); exit 1 if any.
Surface path (CODEOWNERS): weakening this needs ARCHITECT APPROVED.
"""

from __future__ import annotations

import os
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


def triggers_on_pr(root: yaml.Node, loader: yaml.SafeLoader) -> bool:
    for key in ("on", "true", "True"):  # YAML 1.1 reads a bare `on` key as boolean true
        for _, v in find(root, loader, key):
            on = loader.construct_object(v, deep=True)
            if isinstance(on, str):
                return on == "pull_request"
            if isinstance(on, list):
                return "pull_request" in on
            if isinstance(on, dict):
                return "pull_request" in on
    return False


def check_permissions(node, loader, line, where, on_pr, allowed, report):
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
                report(line, "id-token: write in a workflow triggered by pull_request")
            elif not allowed:
                report(line, "id-token: write outside the allowlist")
        elif on_pr and value not in ("read", "none"):
            report(line, f"permissions {scope}: {value} at {where} in a workflow triggered by pull_request (read or none only)")


def check_file(path: str, allow: set[str]) -> list[str]:
    out: list[str] = []

    def report(line: int, msg: str) -> None:
        out.append(f"{path}:{line}: {msg}")

    try:
        with open(path, encoding="utf-8") as fh:
            loader = yaml.SafeLoader(fh.read())
        try:
            root = loader.get_single_node()
            if root is None or not isinstance(root, yaml.MappingNode):
                report(1, "workflow is not a YAML mapping (parse failure fails the guard)")
                return out
            on_pr = triggers_on_pr(root, loader)
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


def main(argv: list[str]) -> int:
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
