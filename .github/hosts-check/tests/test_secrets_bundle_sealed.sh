#!/usr/bin/env bash
# secrets-bundle.sh carries the inventory wrapper's sealed copy (docs/specs/2026-11-private-values-on-the-box.md, choice 2): the keys
# user's bundle takes /etc/agent-keys-inventory-sealed/inventory.sops.json as inventory-sealed/inventory.sops.json when it exists, and
# never the invops-only working copy, its tag key or the recipients file. Run with stand-ins for sops and age-keygen (plumbing only).
#   1. the sealed file present: the bundle's tar lists it under inventory-sealed/ with the same bytes, beside prod/.
#   2. the sealed file absent: the bundle holds prod only and the run passes.
#   3. the decoy working copy, tag key and recipients file beside the sealed folder's parent are not in the bundle.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
role=$root/hosts/ansible/roles/agent_box
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/keys/prod" "$t/keys/secrets-bundle" "$t/libexec" "$t/sealed" "$t/inv"
echo prod-file > "$t/keys/prod/home.tfvars"
printf 'BUNDLE_KEEP=3\n' > "$t/keys/secrets-bundle/settings.env"
echo x > "$t/keys/secrets-bundle/age-identity.txt"
cat > "$t/libexec/age-keygen" <<'EOS'
#!/bin/bash
echo age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
EOS
cat > "$t/libexec/sops" <<'EOS'
#!/bin/bash
out=""; prev=""; for a in "$@"; do [[ $prev == --output ]] && out=$a; prev=$a; done
cp -- "${@: -1}" "$out"
EOS
chmod +x "$t/libexec/"*
sed -e "s|^keys=.*|keys=$t/keys|" -e "s|^libexec=.*|libexec=$t/libexec|" -e "s|^sealed=.*|sealed=$t/sealed/inventory.sops.json|" "$role/files/secrets-bundle.sh" > "$t/secrets-bundle.sh"
for v in keys libexec sealed; do grep -q "^$v=$t" "$t/secrets-bundle.sh" || { bad "the bundle script no longer sets $v on its own line"; exit 1; }; done
listing() { tar -tf "$(ls -1 "$t/keys/secrets-bundle/bundles"/bundle-*.sops.json | tail -n 1)" | sort | tr '\n' ' '; }
bundle() { rm -rf "$t/keys/secrets-bundle/bundles"; HOME=$t bash "$t/secrets-bundle.sh" >/dev/null 2>"$t/err" || { cat "$t/err"; return 1; }; }

# decoys: the invops-only files must never reach the bundle
echo "working-copy-address: 10.9.8.7" > "$t/inv/hosts.yml"; echo tagkey > "$t/inv/tag.key"; echo age1x > "$t/inv/recipients.txt"

echo "SEALED-BYTES" > "$t/sealed/inventory.sops.json"
bundle; l=$(listing)
[[ $l == *inventory-sealed/inventory.sops.json* && $l == *prod/* ]] && ok "1. the sealed copy is in the bundle as inventory-sealed/inventory.sops.json, beside prod/" || bad "1. bundle lists: $l"
x=$(mktemp -d); tar -xf "$(ls -1 "$t/keys/secrets-bundle/bundles"/bundle-*.sops.json | tail -n 1)" -C "$x"
cmp -s "$x/inventory-sealed/inventory.sops.json" "$t/sealed/inventory.sops.json" && ok "1b. the member holds the sealed file's bytes" || bad "1b. the member differs"
[[ $l != *hosts.yml* && $l != *tag.key* && $l != *recipients* ]] && ok "3. no working copy, tag key or recipients file in the bundle" || bad "3. bundle lists: $l"
rm -f "$t/sealed/inventory.sops.json"
bundle; l=$(listing)
[[ $l == *prod/* && $l != *inventory-sealed* ]] && ok "2. no sealed copy: the bundle holds prod only and the run passes" || bad "2. bundle lists: $l"
exit "$fail"
