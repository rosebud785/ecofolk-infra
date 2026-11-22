#!/usr/bin/env bash
# fetch-hcl2json.sh — ecofolk-infra#162 (Architect ruling c7086246324, permission ruling c7086... option (c)).
# Downloads hcl2json (github.com/tmccombs/hcl2json, HashiCorp hcl/v2) at a PINNED version and verifies it against a
# sha256 hardcoded HERE, never fetched at run time, then prints the path of the verified executable on stdout.
#
# hcl2json runs ONLY in CI (Architect, infra#162): only linux/amd64 is pinned, so on any other platform this exits 2
# without downloading anything. Locally, the jq rules are judged against committed JSON fixtures instead
# (scripts/tests/hcl/*.json), and CI proves those fixtures are exactly what the pinned binary emits.
#
# Usage: fetch-hcl2json.sh <empty-or-new-dir>      -> prints <dir>/hcl2json
# Exit: 0 ok; 1 download or checksum failure; 2 unsupported platform / bad usage.
# Surface path (CODEOWNERS): weakening this needs ARCHITECT APPROVED.
set -uo pipefail

VERSION=0.6.9
# sha256 of the release asset `hcl2json_linux_amd64` (hcl2json_0.6.9_checksums.txt, v0.6.9).
SHA256_LINUX_AMD64=b609e37094948c0b77cd8c6c0baaf8af2bd168c685c6e3334d671cc9692c34a5

dest="${1:-}"
[ -n "$dest" ] || { echo "usage: fetch-hcl2json.sh <dir>" >&2; exit 2; }
os="$(uname -s)"; arch="$(uname -m)"
if [ "$os" != Linux ] || { [ "$arch" != x86_64 ] && [ "$arch" != amd64 ]; }; then
  echo "fetch-hcl2json: only linux/amd64 is pinned (this is $os/$arch); hcl2json runs in CI only" >&2
  exit 2
fi
mkdir -p "$dest" || exit 1
bin="$dest/hcl2json"
curl -fsSL --retry 3 --max-time 120 -o "$bin.part" \
  "https://github.com/tmccombs/hcl2json/releases/download/v${VERSION}/hcl2json_linux_amd64" \
  || { echo "fetch-hcl2json: download failed" >&2; exit 1; }
got="$(sha256sum "$bin.part" | cut -d' ' -f1)"
if [ "$got" != "$SHA256_LINUX_AMD64" ]; then
  echo "fetch-hcl2json: sha256 mismatch (got $got, pinned $SHA256_LINUX_AMD64)" >&2
  exit 1
fi
mv "$bin.part" "$bin" && chmod 0755 "$bin" || exit 1
echo "$bin"
