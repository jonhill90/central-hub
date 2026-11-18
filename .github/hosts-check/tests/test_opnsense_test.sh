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

printf '%s\n' '{"name": "daldopdemo01", "address": "10.1.30.199", "keycloak_address": "192.0.2.10",
  "cores": 1, "memory_mb": 3072, "disk_gb": 16, "proxmox_node_name": "examplehv01"}' > "$work/settings.json"
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyExampleKeyExampleKeyExampleKey keys@agent-box opnsense-test" > "$work/key.pub"   # the wrapper's own comment holds a space
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
grep -q 'ifconfig_vtnet0="inet 10.1.30.199/24"' "$ud" && grep -q 'defaultrouter="10.1.30.1"' "$ud" \
  && ok "static dev address, gateway dev's .1" || bad "address or gateway in user-data"
grep -q 'PasswordAuthentication no' "$ud" && ! grep -q 'PasswordAuthentication yes' "$ud" && grep -q 'PermitRootLogin prohibit-password' "$ud" \
  && ok "SSH by key only" || bad "SSH password logins not off"
grep -q 'firstboot_freebsd_update_enable=NO' "$ud" && ok "first-boot freebsd-update skipped" || bad "freebsd-update not skipped"
# /etc/rc reads rc.conf once, so this boot's netif, routing and freebsd-update read the settings from rc.conf.d.
grep -qF "'ifconfig_DEFAULT=\"\"' 'ifconfig_vtnet0=\"inet 10.1.30.199/24\"' > /etc/rc.conf.d/network" "$ud" \
  && grep -qF "'defaultrouter=\"10.1.30.1\"' > /etc/rc.conf.d/routing" "$ud" \
  && grep -qF "'firstboot_freebsd_update_enable=\"NO\"' > /etc/rc.conf.d/firstboot_freebsd_update" "$ud" \
  && ok "first boot reads the address, gateway and update skip from rc.conf.d" || bad "rc.conf.d settings for the first boot"
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
    "LAN static on vtnet0": (t("interfaces/lan/if"), t("interfaces/lan/ipaddr"), t("interfaces/lan/subnet")) == ("vtnet0", "10.1.30.199", "24"),
    "gateway dev .1": t("OPNsense/Gateways/gateway_item/gateway") == "10.1.30.1" and t("interfaces/lan/gateway") == "DEV_GW",
    "DNS dev .1": t("system/dnsserver") == "10.1.30.1",
    "GUI https on LAN only": (t("system/webgui/protocol"), t("system/webgui/interfaces")) == ("https", "lan"),
    "SSH on, key only, LAN only": t("system/ssh/enabled") == "enabled" and c.find("system/ssh/passwordauth") is None and t("system/ssh/interfaces") == "lan",
    "root hash from the proof": t("system/user[name='root']/password") == "$6$salt$roothash",
    "proof admin uid 2000 in admins": t("system/user[name='proofadmin']/uid") == "2000" and "2000" in [m.text for m in c.findall("system/group[name='admins']/member")],
    "proof CA in the trust store": c.find("ca/crt") is not None,
    "the plugin server is under system, where OPNsense reads it": c.find("authserver") is None and c.find("system/authserver") is not None,
    "plugin server named keycloak-proof": t("system/authserver/type") == "openidconnect" and t("system/authserver/name") == "keycloak-proof",
    "app code keycloak, as the lab client": t("system/authserver/openidconnect_app_code") == "keycloak",
    "issuer is the box's Keycloak": t("system/authserver/openidconnect_provider_url") == "https://192.0.2.10:8443/realms/opnsense-proof",
    "PAR disabled": t("system/authserver/openidconnect_par_mode") == "disabled",
    "shared signals off": t("system/authserver/openidconnect_ssf_enabled") == "0",
    "logout notifications off": t("system/authserver/openidconnect_logout_notifications") == "off",
    "admission approval": t("system/authserver/openidconnect_bootstrap_mode") == "approval",
    "root not allowed": t("system/authserver/openidconnect_allow_root") == "0",
    "no account on first login": t("system/authserver/openidconnect_create_users") == "0",
}
bad = [k for k, v in checks.items() if not v]
print("\n".join("ok - config.xml: " + k for k, v in checks.items() if v))
print("\n".join("FAIL - config.xml: " + k for k in bad))
sys.exit(1 if bad else 0)
PY
then :; else fails=$((fails + 1)); fi

# The realm: one confidential client with PKCE S256 and only the VM's origin, two users.
python3 -I "$seed" realm "$work/settings.json" "$work/proof" "$work/realm.json"
python3 -I - "$work/realm.json" <<'PY' && ok "realm: confidential client, PKCE S256, the lab client's exact callback and logout URIs" || bad "realm shape"
import json, sys
r = json.load(open(sys.argv[1]))
c = r["clients"][0]
assert r["realm"] == "opnsense-proof" and len(r["clients"]) == 1
assert c["clientId"] == "opnsense" and c["publicClient"] is False and c["directAccessGrantsEnabled"] is False
assert c["redirectUris"] == ["https://10.1.30.199/api/openidconnect/auth/callback/keycloak"]
assert c["attributes"]["post.logout.redirect.uris"] == "https://10.1.30.199/api/openidconnect/auth/logouttestcallback/keycloak"
assert c["attributes"]["pkce.code.challenge.method"] == "S256"
assert sorted(u["username"] for u in r["users"]) == ["proof-stranger", "proof-user"]
assert c["secret"] == "${KC_PROOF_CLIENT_SECRET}"
assert sorted(u["credentials"][0]["value"] for u in r["users"]) == ["${KC_PROOF_STRANGER_PASS}", "${KC_PROOF_USER_PASS}"]
PY
if grep -qe 'client-secret-example' -e 'user-pass-example' -e 'stranger-pass-example' "$work/realm.json"; then bad "the realm file holds a secret"; else ok "the realm file holds placeholders, not the secret or passwords"; fi

# Refusals: an address outside dev, the gateway itself, a bad name, a key that is not one ed25519 key.
refuse() { # label, settings JSON
  echo "$2" > "$work/bad.json"
  if python3 -I "$seed" seed "$work/bad.json" "$vlans" "$work/key.pub" "$work/bad" >/dev/null 2>&1; then bad "accepted $1"; else ok "refuses $1"; fi
}
refuse "an address in prod" '{"name": "daldopdemo01", "address": "10.1.10.57", "keycloak_address": "192.0.2.10"}'
refuse "dev's gateway address" '{"name": "daldopdemo01", "address": "10.1.30.1", "keycloak_address": "192.0.2.10"}'
refuse "a name outside STD-0001" '{"name": "OPNsense", "address": "10.1.30.199", "keycloak_address": "192.0.2.10"}'
printf 'ssh-rsa AAAA x\nssh-ed25519 AAAA y\n' > "$work/two.pub"
if python3 -I "$seed" seed "$work/settings.json" "$vlans" "$work/two.pub" "$work/bad" >/dev/null 2>&1; then bad "accepted two keys"; else ok "refuses a key file that is not one ed25519 key"; fi
printf 'ssh-ed25519 AAAA x\nssh-ed25519 BBBB y\n' > "$work/two.pub"
if python3 -I "$seed" seed "$work/settings.json" "$vlans" "$work/two.pub" "$work/bad" >/dev/null 2>&1; then bad "accepted two ed25519 keys"; else ok "refuses two ed25519 keys in one file"; fi
printf '%s\n' 'ssh-ed25519 AAAA keys@agent-box opnsense-test"; touch /tmp/pwn; echo "' > "$work/shell.pub"
if python3 -I "$seed" seed "$work/settings.json" "$vlans" "$work/shell.pub" "$work/bad" >/dev/null 2>&1; then bad "accepted shell characters in the key comment"; else ok "refuses shell characters in the key comment"; fi
printf '%s\n' 'ssh-ed25519 AAAA $(id)' > "$work/shell.pub"
if python3 -I "$seed" seed "$work/settings.json" "$vlans" "$work/shell.pub" "$work/bad" >/dev/null 2>&1; then bad "accepted a command substitution in the key comment"; else ok "refuses a command substitution in the key comment"; fi

# status: dev's host list, the newest start task, and the report's verdict from made-up Proxmox answers.
python3 -I "$seed" dev-hosts "$work/settings.json" "$vlans" > "$work/hosts"
[ "$(wc -l < "$work/hosts")" = 254 ] && head -1 "$work/hosts" | grep -qx '10.1.30.1' && tail -1 "$work/hosts" | grep -qx '10.1.30.254' \
  && ok "status pings dev's 254 host addresses" || bad "dev host list"
[ -z "$(python3 -I "$seed" dev-hosts "$work/settings.json" "$work/missing.yml")" ] && ok "status skips the sweep without the VLAN file" || bad "sweep without the VLAN file"
st=$work/status
mkdir -p "$st"
printf '%s\n' '{"data": [{"type": "qmstart", "starttime": 100, "status": "OK", "upid": "UPID:examplehv01:00001234:00005678:0000ABCD:qmstart:257:agent@pve!dev:"},
  {"type": "qmstart", "starttime": 200, "status": "OK", "upid": "UPID:examplehv01:00001235:00005679:0000ABCE:qmstart:257:agent@pve!dev:"},
  {"type": "qmcreate", "starttime": 300, "upid": "UPID:examplehv01:00001236:0000567A:0000ABCF:qmcreate:257:agent@pve!dev:"}]}' > "$st/tasks.json"
[ "$(python3 -I "$seed" last-start "$st/tasks.json")" = 'UPID:examplehv01:00001235:00005679:0000ABCE:qmstart:257:agent@pve!dev:' ] \
  && ok "status reads the newest start task" || bad "newest start task"
printf '%s\n' '{"data": [{"type": "qmstart", "starttime": 1, "upid": "UPID:x/../../y:qmstart"}]}' > "$work/badtasks.json"
[ -z "$(python3 -I "$seed" last-start "$work/badtasks.json")" ] && ok "status refuses a task id that is not a UPID" || bad "accepted a bad UPID"
echo '{"data": {"vmid": 257, "status": "running", "qmpstatus": "running", "uptime": 900, "cpu": 0.01, "mem": 536870912, "maxmem": 3221225472, "netin": 0, "netout": 0}}' > "$st/current.json"
echo '{"data": {"net0": "virtio=BC:24:11:00:00:01,bridge=dev", "ide2": "local:iso/opnsense-test-257-seed.iso,media=cdrom", "boot": "order=scsi0"}}' > "$st/config.json"
echo '{"data": [{"t": "OK"}]}' > "$st/tasklog.json"
arp() { printf 'IP address HW type Flags HW address Mask Device\n'; printf '%s\n' "$@"; }
verdict() { python3 -I "$seed" status "$work/settings.json" "$st" | sed -n 's/^opnsense-test: status: \(the VM .*\)$/\1/p'; }
arp '10.1.30.199 0x1 0x2 bc:24:11:00:00:01 * eth0' > "$st/arp"
verdict | grep -q '^the VM holds the seed.s address 10.1.30.199$' && ok "status: the VM holds the seed's address" || bad "verdict, seed address"
arp '10.1.30.60 0x1 0x2 bc:24:11:00:00:01 * eth0' '10.1.30.199 0x1 0x0 00:00:00:00:00:00 * eth0' > "$st/arp"
verdict | grep -q 'on 10.1.30.60, not the seed.s 10.1.30.199: the seed script did not set its address' && ok "status: the VM took another address" || bad "verdict, other address"
arp '10.1.30.60 0x1 0x2 bc:24:11:00:00:02 * eth0' > "$st/arp"
verdict | grep -q 'has sent nothing on its NIC' && ok "status: the VM sent nothing" || bad "verdict, silent VM"
sed -i 's/"netout": 0/"netout": 4096/' "$st/current.json"
verdict | grep -q 'answers ARP for no dev address' && ok "status: the VM sends but has no address" || bad "verdict, no address"
sed -i 's/"status": "running"/"status": "stopped"/' "$st/current.json"
verdict | grep -q '^the VM is not running$' && ok "status: the VM is stopped" || bad "verdict, stopped"
w=$files/opnsense-test.sh
if sed -n '/^px_api()/,/^}/p;/^status()/,/^}/p' "$w" | grep -qE -- '-X|--request|--data|-d |POST|PUT|DELETE'; then bad "status makes a call other than GET"
else ok "status makes GET calls only"; fi

# Pins: the wrapper's Keycloak is the digest the identity check pins, and the plugin is Plan's beta5 file.
w=$files/opnsense-test.sh
kc=$(sed -n 's/^image=\(quay.io\/keycloak\/keycloak@sha256:[0-9a-f]*\)$/\1/p' "$here/../identity/test_realm.sh")
grep -qx "KEYCLOAK_IMAGE=$kc" "$w" && ok "Keycloak image is the identity check's 26.8.2 digest" || bad "Keycloak image pin differs"
grep -qx 'PLUGIN_SHA256=4b222b0de4ff9523cf3c86b23e984507e21c9a92a02bafe7cc01e406a41b117c' "$w" && ok "plugin pin is beta5's sha256" || bad "plugin pin"
if grep -q -- '--features-disabled' "$w"; then bad "the proof's Keycloak turns a feature off"; else ok "the proof's Keycloak keeps DPoP on, as the lab does"; fi
grep -q '"ES256" not in json.load' "$w" && ok "prove stops unless discovery lists ES256 for DPoP" || bad "no DPoP discovery check"
grep -q '/var/db/openid-connect/dpop' "$files/opnsense-test-prove.py" && ok "prove checks the plugin's DPoP key store" || bad "no DPoP key check"
grep -q 'DPoP sender constraint</th>' "$files/opnsense-test-prove.py" && ok "prove reads the sign-in test's DPoP sender constraint row" || bad "no DPoP sender constraint check"
grep -q 'no Keycloak sign-in form after {url}\\n{why_no_redirect(page)}' "$files/opnsense-test-prove.py" \
  && ok "a login that doesn't reach Keycloak prints OPNsense's answer and its OIDC log lines" || bad "no reason when the login doesn't redirect"
# Root's login shell on the VM is csh, which refuses `2>/dev/null`: diagnostic reads run under /bin/sh.
grep -q 'vm("/bin/sh -c " + shlex.quote(cmd))' "$files/opnsense-test-prove.py" && ok "the VM's diagnostic reads run under /bin/sh, not root's csh" || bad "diagnostic reads run in csh"
# No sh-only redirect may reach root's csh: every `2>` or `2>&1` command goes through on_vm (/bin/sh).
if grep -n 'vm("' "$files/opnsense-test-prove.py" | grep -v 'on_vm("' | grep -q '2>'; then bad "a vm() command uses a sh-only redirect, which csh refuses"
else ok "no vm() command passes a sh-only redirect to csh"; fi
# A top-level assignment must not rebind one of the prover's functions: run 9 (2026-11-18) bound `read` to a
# string after the DPoP check, and item 3's read("stranger.pass") failed with "'str' object is not callable".
python3 -I - "$files/opnsense-test-prove.py" <<'PY' && ok "no top-level name in prove rebinds one of its functions" || bad "prove rebinds one of its own functions"
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
funcs = {n.name for n in tree.body if isinstance(n, ast.FunctionDef)}
bound = {t.id for n in tree.body if isinstance(n, (ast.Assign, ast.AnnAssign, ast.AugAssign))
         for t in (n.targets if isinstance(n, ast.Assign) else [n.target]) if isinstance(t, ast.Name)}
clash = funcs & bound
if clash:
    print("rebinds:", ", ".join(sorted(clash)))
sys.exit(1 if clash else 0)
PY
grep -q 'if last_status\["code"\] == 404:' "$files/opnsense-test-prove.py" && grep -q "get('%s')" "$files/opnsense-test-prove.py" \
  && ok "a 404 from the login prints what the authentication factory lists and returns" || bad "no factory read on a 404"
grep -q 'refused, VM 256 (the lab test copy) exists' "$w" && grep -q 'g.get("vmid") == 256' "$w" \
  && ok "plan refuses while VM 256, the lab test copy, exists" || bad "no refusal while the lab test copy exists"
# Item 10 (D-0037 rule 5): Keycloak stopped with the plugin's server on, then root's password. The wrapper hands
# the prover the container's name; the prover stops it, shows the VM can't reach the issuer, then signs root in.
grep -q '"$sshkey" "$files/known_hosts" "$KC_NAME"$' "$w" && ok "prove gets the Keycloak container's name" || bad "prove lacks the container's name"
grep -q '\["podman", "stop", "--time", "10", kc_name\]' "$files/opnsense-test-prove.py" && grep -q 'set_server_enabled(True)' "$files/opnsense-test-prove.py" \
  && grep -q '!= \["unreachable"\]:' "$files/opnsense-test-prove.py" && grep -q 'proof item 10: with the OIDC server enabled and the proof.s Keycloak stopped' "$files/opnsense-test-prove.py" \
  && ok "item 10 stops Keycloak with the plugin's server on, checks the VM can't reach it, then signs root in" || bad "no Keycloak-stopped root sign-in"
# Item 10 must be the prover's last sign-in: nothing after it may need Keycloak.
python3 -I - "$files/opnsense-test-prove.py" <<'PY' && ok "item 10 runs after every item that needs Keycloak" || bad "an item that needs Keycloak runs after item 10"
import sys
t = open(sys.argv[1]).read()
stop = t.index('["podman", "stop"')
sys.exit(1 if any(t.find(s, stop) != -1 for s in ("keycloak_sign_in(", "approve(", "get(op, base + \"/api/openidconnect")) else 0)
PY
grep -q 'VMID=257$' "$w" && ok "the wrapper's VM ID is 257" || bad "VM ID"
# The token can't delete files on local: destroy targets only the VM, and the seed leaves the state.
code=$(grep -v '^[[:space:]]*#' "$w")   # code lines only, so a comment can't pass or fail these
if grep -q 'plan -destroy' <<<"$code" && ! grep 'plan -destroy' <<<"$code" | grep -vq -- '-target="$vm_res"'; then ok "destroy targets only the VM"; else bad "destroy may delete files on local"; fi
grep -q 'tofu state rm "$seed_res"' <<<"$code" && ok "the seed ISO leaves the state instead of being deleted" || bad "seed not dropped from the state"
grep -q 'refused, VM $VMID is in the state' <<<"$code" && ok "plan refuses while the VM is in the state, so a new seed never replaces a file" || bad "plan may replace the seed file"
# One seed file per seed: the ISO is built byte for byte the same, destroy keeps the seed in the state, and plan keeps
# a seed whose file name matches the new build.
grep -q 'SOURCE_DATE_EPOCH=0 xorriso' <<<"$code" && grep -q 'touch -d @0' <<<"$code" && ok "the seed ISO is built the same each time" || bad "the seed ISO is not reproducible"
if sed -n '/^    destroy)$/,/^      ;;$/p' <<<"$code" | grep -q 'state rm'; then bad "destroy drops the seed from the state"; else ok "destroy keeps the seed in the state, for reuse"; fi
grep -q 'if \[\[ $have == "$want" \]\]' <<<"$code" && ok "plan reuses an unchanged seed" || bad "plan never reuses the seed"
# The proof's Keycloak: prod profile (start-dev opens 8080 whatever --http-enabled says), and only loopback is exempt.
if grep -q 'start-dev' <<<"$code"; then bad "the proof's Keycloak runs start-dev"; else ok "the proof's Keycloak runs start, not start-dev"; fi
grep -q 'start --db=dev-file --cache=local --import-realm --http-enabled=false' <<<"$code" && ok "start uses the dev-file database, local caches and no HTTP" || bad "start options"
# OPNsense 26.1 writes the GUI certificate under lighttpd_webgui (core src/etc/inc/plugins.inc.d/webgui.inc), not /var/etc.
grep -q "cat /usr/local/etc/lighttpd_webgui/cert.pem' > \"\$proof/gui.pem\"" <<<"$code" && ! grep -q '/var/etc/cert.pem' <<<"$code" \
  && ok "prove reads the GUI certificate from where OPNsense 26.1 writes it" || bad "GUI certificate path"

[ "$fails" = 0 ] || { echo "$fails failed"; exit 1; }
echo "opnsense-test: all checks passed"
