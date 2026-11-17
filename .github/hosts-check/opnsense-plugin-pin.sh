#!/usr/bin/env bash
# Proof item 1's attestation half (docs/runbooks/prove-opnsense-sign-in-on-dev.md): the os-openid-connect package the
# opnsense-test wrapper pins is downloaded, checked against the pinned SHA-256, and its build provenance verified
# with `gh attestation verify` as the plugin's docs/setup/install.md gives it: signed by the repository's own
# build.yml on a GitHub-hosted runner. The box checks the same SHA-256 before the file leaves it, so the file the
# VM gets is the one verified here. Needs: curl, sha256sum, gh with GH_TOKEN (read-only is enough).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
wrapper=$here/../../hosts/ansible/roles/agent_box/files/opnsense-test.sh
url=$(sed -n 's/^PLUGIN_URL=\(https:\/\/github\.com\/jpawlowski\/opnsense-openid-connect\/releases\/download\/[^ ]*\.pkg\)$/\1/p' "$wrapper")
sha=$(sed -n 's/^PLUGIN_SHA256=\([0-9a-f]\{64\}\)$/\1/p' "$wrapper")
[ -n "$url" ] && [ -n "$sha" ] || { echo "FAIL: PLUGIN_URL or PLUGIN_SHA256 not found in $wrapper" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for try in 1 2 3; do
  curl -sS --fail -L -o "$work/plugin.pkg" "$url" && break
  [ "$try" = 3 ] && exit 1
  sleep $((try * 15))
done
echo "$sha  $work/plugin.pkg" | sha256sum -c --quiet - || { echo "FAIL: $url does not match $sha" >&2; exit 1; }
echo "plugin-pin: $(basename "$url") matches sha256 $sha"
gh attestation verify "$work/plugin.pkg" \
  -R jpawlowski/opnsense-openid-connect \
  --signer-workflow jpawlowski/opnsense-openid-connect/.github/workflows/build.yml \
  --deny-self-hosted-runners
echo "plugin-pin: build provenance verified"
