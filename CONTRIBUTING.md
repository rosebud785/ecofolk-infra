# Contributing to ecofolk-infra

This repo is **public**. Nothing in it may hold a secret, and no pull-request path may obtain cloud
credentials (see [README.md](README.md)). Run the checks in README's *Running the checks locally*
before you push.

## The boundary

These hold for every change, by a person or a cloud worker:

- **No credentials.** No service-account keys, secrets, tfvars with values or state files, committed
  or referenced. Secret Manager holds empty containers only.
- **No IAM.** No `google_*_iam_*`, `google_service_account_key`, Workload Identity pools or providers,
  or billing bindings. When a change needs one, leave a `# LOCAL FOLLOW-UP:` comment naming the binding
  and list it in the PR body; a local session adds it.
- **No `id-token`.** No workflow but `infra-apply.yml` holds `id-token: write`, no workflow uses
  `pull_request_target`, and every `uses:` is pinned to a full commit SHA with a version comment
  (`scripts/check-workflows.sh`).
- **Cloud workers push to `claude/*` branches only**, never to `main`. Changes reach `main` only through
  a reviewed PR, merged locally. Real `plan`/`apply` runs only from `main` (README: *Plan and apply*), so a PR proves
  itself with the checks: `terraform test` with `mock_provider`, policy, lint, region pin.
- **Region:** `northamerica-northeast1` for everything regional (`scripts/check-region-pin.sh`).
- **Docs:** a module change regenerates its README block (`bash scripts/check-tf-docs.sh --fix`).

## Copying anything in from a private repo

Use this checklist whenever a file, or part of one, comes from a private repo into this one. CI's
`secret-scan` job (gitleaks over the full history of what the PR will merge: all of `main` plus every
commit in the PR, not other branches; config in [`.gitleaks.toml`](.gitleaks.toml)) is the backstop,
not the check.

1. **Copy files, never history.** No `git subtree`, no cherry-picks from a private repo, and no
   `git push` of a private branch to this remote. Write or copy the files fresh and commit them here.
2. **Scan before committing.** Run gitleaks locally on exactly what you are adding
   (`gitleaks dir` takes one path, so loop over the files):

   ```bash
   for f in <files you are adding>; do
     gitleaks dir --config .gitleaks.toml --redact --exit-code 1 "$f" || echo "LEAK: $f"
   done
   ```

3. **Not allowed** unless it is deliberately public and the PR body says so:
   - LAN IP addresses or hostnames (private ranges, `*.home.arpa`, `*.local`);
   - host or device names;
   - personal email addresses;
   - GCP project numbers and service-account addresses;
   - tfvars or tfstate values;
   - anything from a `.env` file or a password manager.
4. **Compare against the source, file by file**, and write in the PR body what was removed or
   generalised. "Copied verbatim" is a valid answer only if it is true.
5. **If something slips through: rotate first, rewrite history second.** A public push may already
   be cached or cloned, so treat the value as exposed the moment it is pushed.

## Allowlisting a scanner finding

Only through [`.gitleaksignore`](.gitleaksignore) (finding fingerprints), and every entry carries a
comment saying why. Never loosen a rule in `.gitleaks.toml` to get green. Both files are surface paths
in [CODEOWNERS](CODEOWNERS), so changing them needs `ARCHITECT APPROVED <sha>`.

`.gitleaks.toml`, `.gitleaksignore` and this file are public too: never write a real hostname,
address, email or identifier into them, because naming it there is the leak.
