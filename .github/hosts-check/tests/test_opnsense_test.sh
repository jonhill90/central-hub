#!/usr/bin/env bash
# The opnsense-test wrapper's helper (opnsense-test-seed.py) and pins, offline: the seed ISO's first-boot script,
# the config.xml OPNsense 26.1 first boots with, the proof's Keycloak realm, and the refusals. Made-up values.
# Needs: python3 with PyYAML.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
files=$root/hosts/ansible/roles/agent_box/files
seed=$files/opnsense-test-seed.py
vlans=$root/hosts/ansible/inventories/home/group_vars/all/vlans.yml
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0
ok() { echo "ok - $1"; }
bad() { echo "FAIL - $1"; fails=$((fails + 1)); }

printf '%s\n' '{"name": "daldopdemo01", "address": "10.1.30.57", "keycloak_address": "10.1.50.9",
  "cores": 1, "memory_mb": 3072, "disk_gb": 16, "proxmox_node_name": "examplehv01"}' > "$work/settings.json"
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyExampleKeyExampleKeyExampleKey keys@agentbox" > "$work/key.pub"
mkdir -p "$work/proof"
printf '%s\n' '-----BEGIN CERTIFICATE-----' 'MIIBexample' '-----END CERTIFICATE-----' > "$work/proof/ca.pem"
echo '$6$salt$roothash' > "$work/proof/root.hash"
echo '$6$salt$adminhash' > "$work/proof/proofadmin.hash"
echo 'client-secret-example' > "$work/proof/client.secret"
echo 'user-pass-example' > "$work/proof/user.pass"
echo 'stranger-pass-example' > "$work/proof/stranger.pass"

# The seed: hostname, a root script that sets the static address, dev's gateway, root's key, and no password logins.
python3 -I "$seed" seed "$work/settings.json" "$vlans" "$work/key.pub" "$work/seed"
ud=$work/seed/user-data
grep -q '^local-hostname: daldopdemo01$' "$work/seed/meta-data" && ok "meta-data names the VM" || bad "meta-data hostname"
head -1 "$ud" | grep -q '^#!/bin/sh$' && [ -x "$ud" ] && ok "user-data is an executable script, which nuageinit runs as root" || bad "user-data is not a script"
grep -q 'ifconfig_vtnet0="inet 10.1.30.57/24"' "$ud" && grep -q 'defaultrouter="10.1.30.1"' "$ud" \
  && ok "static dev address, gateway dev's .1" || bad "address or gateway in user-data"
grep -q 'PasswordAuthentication no' "$ud" && ! grep -q 'PasswordAuthentication yes' "$ud" && grep -q 'PermitRootLogin prohibit-password' "$ud" \
  && ok "SSH by key only" || bad "SSH password logins not off"
grep -q 'firstboot_freebsd_update_enable=NO' "$ud" && ok "first-boot freebsd-update skipped" || bad "freebsd-update not skipped"
grep -qF "$(cat "$work/key.pub")" "$ud" && ok "root's key is the box key" || bad "root key missing"

# config.xml: parses, and holds what design v4 and Plan's conditions ask for.
python3 -I "$seed" config "$work/settings.json" "$vlans" "$work/key.pub" "$work/proof" "$work/config.xml"
if python3 -I - "$work/config.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
c = ET.parse(sys.argv[1]).getroot()
def t(path):
    e = c.find(path)
    return None if e is None else (e.text or "")
checks = {
    "no WAN": c.find("interfaces/wan") is None,
    "no DHCP or DNS server": c.find("dnsmasq") is None and c.find("unbound") is None,
    "LAN static on vtnet0": (t("interfaces/lan/if"), t("interfaces/lan/ipaddr"), t("interfaces/lan/subnet")) == ("vtnet0", "10.1.30.57", "24"),
    "gateway dev .1": t("OPNsense/Gateways/gateway_item/gateway") == "10.1.30.1" and t("interfaces/lan/gateway") == "DEV_GW",
    "DNS dev .1": t("system/dnsserver") == "10.1.30.1",
    "GUI https on LAN only": (t("system/webgui/protocol"), t("system/webgui/interfaces")) == ("https", "lan"),
    "SSH on, key only, LAN only": t("system/ssh/enabled") == "enabled" and c.find("system/ssh/passwordauth") is None and t("system/ssh/interfaces") == "lan",
    "root hash from the proof": t("system/user[name='root']/password") == "$6$salt$roothash",
    "proof admin uid 2000 in admins": t("system/user[name='proofadmin']/uid") == "2000" and "2000" in [m.text for m in c.findall("system/group[name='admins']/member")],
    "proof CA in the trust store": c.find("ca/crt") is not None,
    "plugin server named keycloak-proof": t("authserver/type") == "openidconnect" and t("authserver/name") == "keycloak-proof",
    "issuer is the box's Keycloak": t("authserver/openidconnect_provider_url") == "https://10.1.50.9:8443/realms/opnsense-proof",
    "PAR disabled": t("authserver/openidconnect_par_mode") == "disabled",
    "shared signals off": t("authserver/openidconnect_ssf_enabled") == "0",
    "logout notifications off": t("authserver/openidconnect_logout_notifications") == "off",
    "admission approval": t("authserver/openidconnect_bootstrap_mode") == "approval",
    "root not allowed": t("authserver/openidconnect_allow_root") == "0",
    "no account on first login": t("authserver/openidconnect_create_users") == "0",
}
bad = [k for k, v in checks.items() if not v]
print("\n".join("ok - config.xml: " + k for k, v in checks.items() if v))
print("\n".join("FAIL - config.xml: " + k for k in bad))
sys.exit(1 if bad else 0)
PY
then :; else fails=$((fails + 1)); fi

# The realm: one confidential client with PKCE S256 and only the VM's origin, two users.
python3 -I "$seed" realm "$work/settings.json" "$work/proof" "$work/realm.json"
python3 -I - "$work/realm.json" <<'PY' && ok "realm: confidential client, PKCE S256, redirect only to the VM" || bad "realm shape"
import json, sys
r = json.load(open(sys.argv[1]))
c = r["clients"][0]
assert r["realm"] == "opnsense-proof" and len(r["clients"]) == 1
assert c["clientId"] == "opnsense" and c["publicClient"] is False and c["directAccessGrantsEnabled"] is False
assert c["redirectUris"] == ["https://10.1.30.57/*"] and c["attributes"]["pkce.code.challenge.method"] == "S256"
assert sorted(u["username"] for u in r["users"]) == ["proof-stranger", "proof-user"]
PY

# Refusals: an address outside dev, the gateway itself, a bad name, a key that is not one ed25519 key.
refuse() { # label, settings JSON
  echo "$2" > "$work/bad.json"
  if python3 -I "$seed" seed "$work/bad.json" "$vlans" "$work/key.pub" "$work/bad" >/dev/null 2>&1; then bad "accepted $1"; else ok "refuses $1"; fi
}
refuse "an address in prod" '{"name": "daldopdemo01", "address": "10.1.10.57", "keycloak_address": "10.1.50.9"}'
refuse "dev's gateway address" '{"name": "daldopdemo01", "address": "10.1.30.1", "keycloak_address": "10.1.50.9"}'
refuse "a name outside STD-0001" '{"name": "OPNsense", "address": "10.1.30.57", "keycloak_address": "10.1.50.9"}'
printf 'ssh-rsa AAAA x\nssh-ed25519 AAAA y\n' > "$work/two.pub"
if python3 -I "$seed" seed "$work/settings.json" "$vlans" "$work/two.pub" "$work/bad" >/dev/null 2>&1; then bad "accepted two keys"; else ok "refuses a key file that is not one ed25519 key"; fi

# Pins: the wrapper's Keycloak is the digest the identity check pins, and the plugin is Plan's beta5 file.
w=$files/opnsense-test.sh
kc=$(sed -n 's/^image=\(quay.io\/keycloak\/keycloak@sha256:[0-9a-f]*\)$/\1/p' "$here/../identity/test_realm.sh")
grep -qx "KEYCLOAK_IMAGE=$kc" "$w" && ok "Keycloak image is the identity check's 26.8.1 digest" || bad "Keycloak image pin differs"
grep -qx 'PLUGIN_SHA256=4b222b0de4ff9523cf3c86b23e984507e21c9a92a02bafe7cc01e406a41b117c' "$w" && ok "plugin pin is beta5's sha256" || bad "plugin pin"
grep -q -- '--features-disabled=dpop' "$w" && ok "the proof's Keycloak runs with DPoP off" || bad "DPoP not off"
grep -q 'VMID=257$' "$w" && ok "the wrapper's VM ID is 257" || bad "VM ID"

[ "$fails" = 0 ] || { echo "$fails failed"; exit 1; }
echo "opnsense-test: all checks passed"
