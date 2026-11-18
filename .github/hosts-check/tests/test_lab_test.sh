#!/usr/bin/env bash
# The lab-test wrapper's helper (lab-test-answer.py), its pins and refusals, and the role's unpacking of the
# assistant, offline. Made-up values. Needs: python3 3.11 or newer (tomllib) with PyYAML, xz, openssl, php.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
role=$root/hosts/ansible/roles/agent_box
files=$role/files
helper=$files/lab-test-answer.py
w=$files/lab-test.sh
vlans=$root/hosts/ansible/inventories/home/group_vars/all/vlans.yml
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0
ok() { echo "ok - $1"; }
bad() { echo "FAIL - $1"; fails=$((fails + 1)); }

settings() { # address name domain
  printf '{"name": "%s", "domain": "%s", "address": "%s", "cores": 2, "memory_mb": 7168, "disk_gb": 32, "proxmox_node_name": "examplehv01"}\n' \
    "$2" "$3" "$1" > "$work/settings.json"
}
settings 10.1.30.198 ddehvdemo01 lab.example
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyExampleKeyExampleKeyExampleKey keys@agent-box lab-test" > "$work/key.pub"
printf '$6$examplesalt$%s\n' "$(printf 'a%.0s' $(seq 1 86))" > "$work/root.hash"

# The answer: valid TOML with the keys the installer needs, dev's address, gateway and DNS, root by key.
python3 -I "$helper" answer "$work/settings.json" "$vlans" "$work/key.pub" "$work/root.hash" "$work/answer.toml"
python3 -I - "$work/answer.toml" <<'PY' && ok "the answer is TOML: root by key and hash, dev's .198/24 via .1, ext4 on sda" || bad "the answer"
import sys, tomllib
a = tomllib.load(open(sys.argv[1], "rb"))
g, n, d = a["global"], a["network"], a["disk-setup"]
assert g["fqdn"] == "ddehvdemo01.lab.example" and g["timezone"] == "UTC" and g["keyboard"] == "en-us"
assert g["root-password-hashed"].startswith("$6$") and "root-password" not in g   # one or the other, never both
assert g["root-ssh-keys"] == [open(sys.argv[1].replace("answer.toml", "key.pub")).read().strip()]
assert g["reboot-on-error"] is False
assert n == {"source": "from-answer", "cidr": "10.1.30.198/24", "gateway": "10.1.30.1", "dns": "10.1.30.1",
             "filter": {"ID_NET_NAME_MAC": "*"}}, n
assert d["filesystem"] == "ext4" and d["disk-list"] == ["sda"] and "filter" not in d
PY
# The data volume holds the copy's own OPNsense disk (16 GB, opnsense-test's minimum) on a 32 GB disk.
python3 -I - "$work/answer.toml" <<'PY' && ok "32 GB leaves the data volume 16 GB or more after root, swap and minfree" || bad "the data volume is too small"
import sys, tomllib
l = tomllib.load(open(sys.argv[1], "rb"))["disk-setup"]["lvm"]
sys.exit(0 if 32 - l["maxroot"] - l["swapsize"] - l["minfree"] >= 16 else 1)
PY

# Refusals: the gateway, an address outside dev, a bad name, a bad domain, a bad key, a bad hash.
refused() { # what
  if python3 -I "$helper" answer "$work/settings.json" "$vlans" "$work/key.pub" "$work/root.hash" "$work/x.toml" 2>/dev/null; then
    bad "accepted $1"
  else
    ok "refuses $1"
  fi
}
settings 10.1.30.1 ddehvdemo01 lab.example; refused "dev's gateway as the address"
settings 10.1.10.198 ddehvdemo01 lab.example; refused "an address outside dev"
settings 10.1.30.198 Demo01 lab.example; refused "a name that is not STD-0001"
settings 10.1.30.198 ddehvdemo01 'lab_example; x'; refused "a domain that is not a DNS name"
settings 10.1.30.198 ddehvdemo01 lab.example
cp "$work/key.pub" "$work/key.good"
echo 'ssh-rsa AAAAB3Nza example' > "$work/key.pub"; refused "a key that is not ed25519"
printf 'ssh-ed25519 AAAA x\nssh-ed25519 BBBB y\n' > "$work/key.pub"; refused "two keys"
cp "$work/key.good" "$work/key.pub"
cp "$work/root.hash" "$work/hash.good"
echo 'plain-password' > "$work/root.hash"; refused "a root password that is not a SHA-512 crypt hash"
cp "$work/hash.good" "$work/root.hash"

# The wrapper's pins: the ISO's sha256, and an ISO release that matches the assistant's.
grep -Eq '^ISO_SHA256=[0-9a-f]{64}$' "$w" && ok "the ISO is pinned by sha256" || bad "no ISO pin"
iso=$(sed -n 's/^ISO_NAME=proxmox-ve_\([0-9]*\.[0-9]*\)-[0-9]*\.iso$/\1/p' "$w")
asst=$(sed -n 's/^agent_box_pve_assistant_version: \([0-9]*\.[0-9]*\)\..*/\1/p' "$role/defaults/main.yml")
[[ -n $iso && $iso == "$asst" ]] && ok "the ISO ($iso) and the assistant ($asst) are the same release" || bad "ISO $iso, assistant $asst"
grep -Eq '^agent_box_pve_assistant_sha256: [0-9a-f]{64}$' "$role/defaults/main.yml" && ok "the assistant is pinned by sha256" || bad "no assistant pin"

# The guards and the refusals the spec names.
grep -q 'refused, VM $OPNSENSE_TEST_VMID (the OPNsense test) exists' "$w" && grep -q '^OPNSENSE_TEST_VMID=257$' "$w" \
  && ok "plan refuses while VM 257 exists" || bad "no refusal while VM 257 exists"
grep -q "refused, dev's state holds" "$w" && grep -q 'refused, a dev rebuild run is going' "$w" \
  && ok "plan refuses while dev is up or a dev rebuild runs" || bad "no dev refusals"
grep -q 'need=$(( $(setting memory_mb) + 2048 ))' "$w" && grep -q 'refused, short on memory' "$w" \
  && ok "plan needs the copy's memory plus the 2048 MiB margin free" || bad "no memory guard"
grep -q 'refused, short on box disk' "$w" && ok "plan needs room on the box for the ISOs" || bad "no disk guard"
grep -q 'refused, VM $VMID is in the state; run lab-test destroy first' "$w" && ok "plan refuses while VM 256 is in the state" || bad "plan with VM 256 in the state"
grep -q -- '-target="$vm_res"' "$w" && ! grep -q 'tofu destroy' "$w" && ok "destroy takes only the VM" || bad "destroy is not targeted"
grep -q -- '--fetch-from iso --answer-file "$files/answer.toml"' "$w" && grep -q '"$assistant" validate-answer' "$w" \
  && ok "the answer is validated, then baked into the ISO" || bad "the ISO is not prepared from the validated answer"
grep -q "grep -cE '(vmx|svm)' /proc/cpuinfo" "$w" && grep -q "test -c /dev/kvm" "$w" && grep -q "stopped, the copy's CPU shows no vmx or svm" "$w" \
  && ok "check stops when the copy's guests would run without KVM" || bad "no nested check"
grep -q '^  plan) guards; tofu_run ;;$' "$w" && grep -q '^  apply) guards; tofu_run ;;$' "$w" \
  && ok "plan and apply both pass the guards" || bad "a build step skips the guards"
grep -Eq '^  - name: lab-test$' "$role/defaults/main.yml" && grep -A1 '^  - name: lab-test$' "$role/defaults/main.yml" | grep -q 'args: \[plan, apply, check, host, lab, firstboot, opnsense, destroy, log\]' \
  && ok "the wrapper list allows plan, apply, check, host, lab, firstboot, opnsense, destroy and log" || bad "the wrapper's sudo arguments"

# host: the inventory the copy's playbook runs with, the real inventory's shape with the copy's own values.
python3 -I "$helper" inventory "$work/settings.json" "$vlans" /keys/lab-test-ssh /work/known_hosts "$work/hosts.yml"
python3 -I - "$work/hosts.yml" <<'PY' && ok "the copy's inventory: one proxmox host, root by the wrapper's key, mgmt .2, vmbr1 MAC locally administered" || bad "the copy's inventory"
import sys, yaml
h = yaml.safe_load(open(sys.argv[1]))["all"]["children"]["proxmox"]["hosts"]
assert list(h) == ["proxmox_host"], h
h = h["proxmox_host"]
assert h["ansible_host"] == "10.1.30.198" and h["ansible_user"] == "root" and h["ansible_ssh_private_key_file"] == "/keys/lab-test-ssh"
assert "UserKnownHostsFile=/work/known_hosts" in h["ansible_ssh_common_args"]
assert h["proxmox_host_mgmt_address"] == "10.1.50.2" and h["proxmox_network_lab_supernet"] == "10.1.0.0/16"
assert int(h["proxmox_vmbr1_mac"].split(":")[0], 16) & 2, "not locally administered"
PY
# host runs the fresh-host steps in the runbook's order: apt, iac-access.sh, the token, iac-access.sh again, vmbr1.
python3 -I - "$w" <<'PY' && ok "host runs apt, iac-access.sh, the token, iac-access.sh again, then vmbr1" || bad "host's order"
import sys
t = open(sys.argv[1]).read()
body = t[t.index("\nhost() {"):]
steps = ["Components: pve-no-subscription", "vm 'sh /root/iac-access.sh'", "pveum user token add iac@pve apply --privsep 1",
         "vm 'sh /root/iac-access.sh'", "playbooks/proxmox-host.yml --tags vmbr1"]
pos = -1
for s in steps:
    pos = body.index(s, pos + 1)
PY
grep -q 'rm -rf "$files/known_hosts" "$files"/\*.part "$files/copy-token" "$files/inventory"' "$w" \
  && ok "destroy removes the copy's token and inventory" || bad "destroy keeps the copy's token"

# host ends with the images: pins, checks, and the storage line read from storage.cfg.
grep -Eq '^NANO_BZ2_SHA256=[0-9a-f]{64}$' "$w" && grep -Eq '^CT_TEMPLATE_SHA512=[0-9a-f]{128}$' "$w" \
  && grep -q 'sha256sum -c --quiet - || { rm -f "$NANO_IMG.bz2.part"' "$w" && grep -q 'sha512sum -c --quiet -' "$w" \
  && ok "the nano image and the Debian 13 template are pinned and checked" || bad "image pins or checks"
grep -q '^  images$' "$w" && ok "host stages the images last" || bad "host does not stage the images"
printf 'dir: local\n\tpath /var/lib/vz\n\tcontent iso,vztmpl,backup\n\nlvmthin: local-lvm\n\tcontent rootdir,images\n' > "$work/storage.cfg"
prog=$(sed -n "s|^content=\$(awk '\(.*\)' /etc/pve/storage.cfg)$|\1|p" "$w")
[[ -n $prog && $(awk "$prog" "$work/storage.cfg") == "iso,vztmpl,backup" ]] \
  && ok "the content line of storage local is read from storage.cfg, not local-lvm's" || bad "the storage.cfg read"

# iac-access.sh, which host runs in the copy: zone lab can be made on an empty host (Zones.pm checks /sdn/zones).
iac=$root/hosts/terraform/home/bootstrap/iac-access.sh
grep -Eq '^acl /sdn/zones 0 ' "$iac" && ! grep -Eq '^acl /sdn/zones 1 ' "$iac" && ! grep -Eq '^acl /sdn 1 ' "$iac" \
  && ok "iac-access.sh lets the token make a zone, without rights in other zones" || bad "iac-access.sh: no /sdn/zones ACL"

# lab: the copy's own values for the three run folders, then the folders in the runbook's order, then mgmt.
mkdir -p "$work/layers"
python3 -I "$helper" layers "$work/settings.json" "$vlans" OPNsense-26.1.6-nano-amd64.img debian-13-standard_13.6-1_amd64.tar.zst "$work/layers"
python3 -I - "$work/layers" "$vlans" <<'PY' && ok "lab's values: the copy's node, STD-0001 names, local MACs, WAN link-down, mgmt .3, the staged files" || bad "lab's values"
import json, os, re, sys
d = sys.argv[1]
v = {f: json.load(open(os.path.join(d, f + ".tfvars.json"))) for f in ("network", "firewall", "remote-access")}
assert all(x["proxmox_node_name"] == "ddehvdemo01" for x in v.values())
assert v["network"]["vlans_file"] == sys.argv[2] and set(v["network"]) == {"proxmox_node_name", "vlans_file"}
fw, ra = v["firewall"], v["remote-access"]
assert fw["firewall_vm_name"] == "dopnwdemo01" and ra["connector_hostname"] == "ddenwdemo01"
assert fw["opnsense_wan_connected"] is False
assert fw["opnsense_image_file_id"] == "local:import/OPNsense-26.1.6-nano-amd64.img"
assert ra["connector_template_file_id"] == "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
assert ra["connector_mgmt_address"] == "10.1.50.3/24"
macs = [fw["opnsense_lan_mac"], fw["opnsense_wan_mac"], ra["connector_eth0_mac"], "02:00:00:00:02:56"]
assert len(set(macs)) == 4 and all(re.fullmatch(r"02(:[0-9a-f]{2}){5}", m) for m in macs), macs
PY
# Each folder's required variables are ones the helper writes: no private value is left for the box to guess.
python3 -I - "$root/hosts/terraform/home" "$work/layers" <<'PY' && ok "lab's values fill every required variable of network, firewall and remote-access" || bad "a run folder variable lab does not set"
import json, os, re, sys
for f in ("network", "firewall", "remote-access"):
    src = open(os.path.join(sys.argv[1], f, "variables.tf")).read()
    blocks = re.findall(r'variable "([a-z0-9_]+)" \{(.*?)\n\}', src, re.S)
    assert blocks, f
    required = {name for name, body in blocks if not re.search(r"^\s*default\s*=", body, re.M)}
    have = set(json.load(open(os.path.join(sys.argv[2], f + ".tfvars.json"))))
    assert required <= have, (f, required - have)
PY
python3 -I - "$w" <<'PY' && ok "lab runs network, firewall, remote-access, then mgmt; remote-access as root@pam, the others by the copy token" || bad "lab's order or sign-in"
import sys
t = open(sys.argv[1]).read()
body = t[t.index("\nlab() {"):]
body = body[:body.index("\n}\n")]
assert body.index("for f in network firewall remote-access; do lab_folder") < body.index("playbooks/proxmox-host.yml --tags mgmt")
f = t[t.index("\nlab_folder() {"):]
f = f[:f.index("\n}\n")]
assert "unset PROXMOX_VE_API_TOKEN PROXMOX_VE_USERNAME PROXMOX_VE_PASSWORD PROXMOX_VE_INSECURE" in f
assert f.index("if [[ $1 == remote-access ]]") < f.index("PROXMOX_VE_USERNAME=root@pam") < f.index("else") \
    < f.index('PROXMOX_VE_API_TOKEN=$(cat "$files/copy-token")')
assert "PROXMOX_VE_ENDPOINT=https://$addr:8006/ SSL_CERT_FILE=$files/copy-ca.pem" in f
assert "-detailed-exitcode" in f and "the second plan is not empty" in f
PY
grep -q 'openssl passwd -6 -stdin < "$files/root.pass" > "$files/root.hash"' "$w" && ok "root's hash is of the password the box keeps" || bad "root's hash and password"
grep -q '"$files/inventory" "$files/state" "$files/copy-ca.pem"' "$w" && ok "destroy removes the copy's run folder states and its CA" || bad "destroy keeps lab's states"

# opnsense: the copy's firewall inventory, in the shape opnsense_lab takes, and the run through the tunnel.
mkdir -p "$work/fwinv/inventory"
if python3 -I "$helper" firewall-inventory "$work/settings.json" "$vlans" 40443 /usr/bin/python3 "$work/fwinv/inventory/opnsense.yml" > /dev/null 2>&1; then
  bad "firewall-inventory wrote an inventory with no copy CA next to it"
else
  ok "firewall-inventory refuses without the copy's CA"
fi
echo pem > "$work/fwinv/copy-ca.pem"
python3 -I "$helper" firewall-inventory "$work/settings.json" "$vlans" 443 /usr/bin/python3 "$work/fwinv/inventory/opnsense.yml" > /dev/null 2>&1 \
  && bad "firewall-inventory took port 443" || ok "firewall-inventory refuses a privileged tunnel port"
python3 -I "$helper" firewall-inventory "$work/settings.json" "$vlans" 40443 /usr/bin/python3 "$work/fwinv/inventory/opnsense.yml"
python3 -I - "$work/fwinv" "$vlans" "$role/../opnsense_lab/meta/argument_specs.yml" "$root/hosts/ansible/inventories/home/hosts.example.yml" <<'PY' \
  && ok "the copy's firewall inventory: localhost on the tunnel's port, TLS bootstrap, every VLAN as hosts.example.yml, made-up private values, every required input but the key" \
  || bad "the copy's firewall inventory"
import ipaddress, os, sys, yaml
d, vlans, specs, example = sys.argv[1:5]
h = yaml.safe_load(open(os.path.join(d, "inventory/opnsense.yml")))["all"]["children"]["opnsense"]["hosts"]["opnsense_fw"]
assert h["ansible_connection"] == "local" and h["ansible_python_interpreter"] == "/usr/bin/python3"
assert h["opnsense_api_host"] == "localhost" and h["opnsense_cert_gui_port"] == 40443
assert h["opnsense_lab_tls_bootstrap"] is True and h["opnsense_lab_ssl_ca_file"] == os.path.join(d, "copy-ca.pem")
assert "opnsense_api_key" not in h and "opnsense_api_secret" not in h and "opnsense_lab_ssl_verify" not in h
assert ipaddress.ip_network(h["opnsense_home_lan_cidr"]) == ipaddress.ip_network("192.0.2.0/24")
assert h["opnsense_dns_zone"].endswith(".test")
lab = yaml.safe_load(open(vlans))["lab_vlans"]
assert h["opnsense_lab_mgmt_tag"] == [v["id"] for v in lab if v["name"] == "mgmt"][0]
ex = yaml.safe_load(open(example))["all"]["children"]["opnsense"]["hosts"]["opnsense_fw"]
assert h["opnsense_lab_vlan_settings"] == ex["opnsense_lab_vlan_settings"], "keep COPY_VLAN_SETTINGS as hosts.example.yml"
assert set(h["opnsense_lab_vlan_settings"]) == {v["name"] for v in lab}
nets = [ipaddress.ip_network(v["cidr"]) for v in lab]
for o in h["opnsense_lab_host_overrides"]:
    assert any(ipaddress.ip_address(o["address"]) in n for n in nets), o
opts = yaml.safe_load(open(specs))["argument_specs"]["main"]["options"]
required = {k for k, v in opts.items() if v.get("required")}
missing = required - set(h) - {"opnsense_api_key", "opnsense_api_secret", "lab_vlans"}
assert not missing, missing
PY
python3 -I - "$w" "$root/hosts/ansible/playbooks/opnsense.yml" <<'PY' && ok "opnsense tunnels to the mgmt gateway's 443, passes the key in a file, skips only the DNS proof, and needs changed=0 on the second run" || bad "opnsense's wiring"
import re, sys
t = open(sys.argv[1]).read()
f = t[t.index("\nopnsense() {"):]
f = f[:f.index("\n}\n")]
assert '-L "127.0.0.1:$port:$gw:443" "root@$addr"' in f and "ExitOnForwardFailure=yes" in f
assert 'firewall-inventory "$settings" "$vlans" "$port" "$py" "$files/inventory/opnsense.yml"' in f
assert '-e @"$files/opnsense-api.vars.json" playbooks/opnsense.yml' in f and "--skip-tags dns_proof" in f
assert "--tags" not in f.replace("--skip-tags", "") and "unset HTTPS_PROXY https_proxy" in f
assert "opnsense-api.secret" in f and "opnsense_api_secret" in f and "kill $tunnel" in f
assert "for n in 1 2; do" in f
pat = re.search(r"grep -Eq '([^']+)' \"\$files/opnsense-run.log\"", f).group(1)
assert re.search(pat, "opnsense_fw                 : ok=57   changed=0    unreachable=0    failed=0    skipped=9", re.M)
assert not re.search(pat, "opnsense_fw                 : ok=57   changed=1    unreachable=0    failed=0    skipped=9", re.M)
pb = open(sys.argv[2]).read()
assert 'api_port: "{{ opnsense_cert_gui_port | default(443) }}"' in pb
PY
grep -q '"$files"/opnsense-api.\* "$files/opnsense-run.log"' "$w" \
  && ok "destroy removes opnsense's log" || bad "destroy keeps opnsense's log"

# firstboot: the console driver against a fake serial console that answers as OPNsense's does (a login, a wrong
# first password, menu 8, then a shell that runs each line with sh), and the first-boot PHP against stubs of
# OPNsense's config, auth and util includes.
mkdir -p "$work/fake/bin" "$work/fake/fw"
cat > "$work/fake/console.py" <<'FAKE'
import os, subprocess, sys
pw, wd, bindir = sys.argv[1:4]
def w(s):
    os.write(1, s.encode() if isinstance(s, str) else s)
def line():
    b = b""
    while True:
        c = os.read(0, 1)
        if not c:
            sys.exit(0)
        if c in (b"\r", b"\n"):
            return b.decode()
        b += c
line()   # the driver's first wake
w("\r\nFreeBSD/amd64 (OPNsense.internal) (ttyu0)\r\n\r\nlogin: ")
while True:
    u = line(); w(u + "\r\n")
    if u != "root":
        w("login: "); continue
    w("Password:"); p = line(); w("\r\n")
    if p == pw:
        break
    w("Login incorrect\r\nlogin: ")
w("  0) Logout   8) Shell\r\n\r\nEnter an option: ")
if line() != "8":
    sys.exit(1)
w("8\r\n\r\nroot@OPNsense:~ # ")
while True:
    cmd = line(); w(cmd + "\r\n")
    if cmd == "exec /bin/sh":
        w("# "); continue
    if cmd == "reboot":
        open(os.path.join(wd, "rebooted"), "w").close(); w("Rebooting...\r\n"); sys.exit(0)
    r = subprocess.run(["sh", "-c", cmd], cwd=wd, capture_output=True, env={"PATH": bindir + ":/usr/bin:/bin"})
    w((r.stdout + r.stderr).replace(b"\n", b"\r\n")); w("# ")
FAKE
printf '#!/bin/sh\n[ "$1" = -q ] && shift\nsha256sum "$1" | cut -d" " -f1\n' > "$work/fake/bin/sha256"
chmod +x "$work/fake/bin/sha256"
head -c 700 /dev/urandom > "$work/fake/payload.bin"
fakeplan() { # commands as a JSON list
  printf '{"passwords": ["opnsense", "right"], "dir": "%s", "files": {"payload.bin": "%s"}, "commands": %s, "reboot": true}\n' \
    "$work/fake/fw/lab-test" "$work/fake/payload.bin" "$1" > "$work/fake/plan.json"
}
fakeplan '["test -s payload.bin", "echo ran > ran.txt"]'
if timeout 120 python3 -I "$files/lab-test-console.py" "$work/fake/plan.json" python3 -I "$work/fake/console.py" right "$work/fake/fw" "$work/fake/bin" > "$work/fake/out" 2>&1 \
  && cmp -s "$work/fake/payload.bin" "$work/fake/fw/lab-test/payload.bin" && [[ -f $work/fake/fw/lab-test/ran.txt && -f $work/fake/fw/rebooted ]] \
  && grep -q 'signed in on the console' "$work/fake/out" && ! grep -q right "$work/fake/out"; then
  ok "the console driver signs in with the second password, sends a file whole, runs the commands and reboots"
else
  bad "the console driver"; cat "$work/fake/out"
fi
rm -rf "$work/fake/fw" && mkdir -p "$work/fake/fw"
fakeplan '["false", "echo ran > ran.txt"]'
if timeout 120 python3 -I "$files/lab-test-console.py" "$work/fake/plan.json" python3 -I "$work/fake/console.py" opnsense "$work/fake/fw" "$work/fake/bin" > "$work/fake/out" 2>&1; then
  bad "the console driver went on past a failed command"
elif [[ ! -e $work/fake/fw/lab-test/ran.txt && ! -e $work/fake/fw/rebooted ]] && grep -q 'the command failed (exit 1): false' "$work/fake/out"; then
  ok "the console driver stops at the first failed command and does not reboot"
else
  bad "the console driver's stop"; cat "$work/fake/out"
fi
grep -q '"socat UNIX-CONNECT:/var/run/qemu-server/100.serial0 STDIO"' "$w" && grep -q 'php opnsense-first-boot.php vtnet0 %s %s vtnet1 root.hash' "$w" \
  && grep -q '"$files"/opnsense-root\.\*' "$w" \
  && ok "firstboot reaches VM 100's serial0 socket, runs the first-boot PHP, and destroy removes OPNsense's root password" \
  || bad "firstboot's wiring"

grep -q '"opnsense-ansible-user.php": sys.argv\[6\], "ansible-apikey.line": sys.argv\[7\]' "$w" \
  && grep -q 'openssl passwd -6 -stdin < "$files/opnsense-api.secret"' "$w" \
  && grep -q 'vm "curl -sk --fail --max-time 10 -K - -o /dev/null https://$gw/api/interfaces/vlan_settings/search_item"' "$w" \
  && grep -q '"$files"/opnsense-root\.\* "$files"/opnsense-api\.\*' "$w" \
  && ! grep -q 'opnsense-api.secret.*sys.argv\|curl[^|]*-u ' "$w" \
  && ok "firstboot sends the API user script and only the key line, checks the API with the secret on stdin, and destroy removes the key" \
  || bad "firstboot's API user wiring"
# The API user command, as the console runs it in its directory, with /root moved to a test folder: the key line goes
# whether the script works or fails, and its exit code comes through.
apicmd=$(python3 -I -c 'import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"\"(cp ansible-apikey\.line [^\"]*)\"\n\s*\" (&& php opnsense-ansible-user\.php;[^\"]*)\"", t)
print(m.group(1) + " " + m.group(2))' "$w")
mkdir -p "$work/apiu/bin"
for want in 0 3; do
  rm -rf "$work/apiu/root" "$work/apiu/dir" && mkdir -p "$work/apiu/root" "$work/apiu/dir"
  echo 'k|$6$x' > "$work/apiu/dir/ansible-apikey.line"; echo h > "$work/apiu/dir/root.hash"
  printf '#!/bin/sh\n[ -s %s/ansible-apikey.line ] || exit 9\nexit %s\n' "$work/apiu/root" "$want" > "$work/apiu/bin/php"
  chmod +x "$work/apiu/bin/php"
  got=0; ( cd "$work/apiu/dir" && PATH=$work/apiu/bin:$PATH sh -c "${apicmd//\/root\//$work/apiu/root/}" ) >/dev/null 2>&1 || got=$?
  if [[ $got == "$want" && ! -e $work/apiu/root/ansible-apikey.line && ! -e $work/apiu/dir/ansible-apikey.line && ! -e $work/apiu/dir/root.hash ]]; then
    ok "the API user command removes the key line and root's hash, and exits $want when the script does"
  else
    bad "the API user command (wanted exit $want, got $got)"
  fi
done

# The first-boot PHP against stubs: config.inc holds the image's default config (config.xml.sample's parts it changes).
mkdir -p "$work/php"
cat > "$work/php/config.inc" <<'STUB'
<?php
$config = json_decode(file_get_contents(getenv('LT_CONFIG')), true);
function &config_read_array() {
    global $config;
    $keys = func_get_args();
    $insert = true;
    if (is_bool(end($keys))) { $insert = array_pop($keys); }
    $cur = &$config;
    foreach ($keys as $k) {
        if (!isset($cur[$k]) || !is_array($cur[$k])) {
            if (!$insert) { $d = []; return $d; }
            $cur[$k] = [];
        }
        $cur = &$cur[$k];
    }
    return $cur;
}
function config_push_array() {
    $keys = func_get_args(); $new = array_pop($keys);
    $a = &call_user_func_array('config_read_array', $keys); $a[] = $new;
}
function generate_uuid() { return 'u' . count($GLOBALS['config']['vlans']['vlan'] ?? []); }
function write_config($desc = '') { global $config; file_put_contents(getenv('LT_CONFIG'), json_encode($config)); }
STUB
cat > "$work/php/auth.inc" <<'STUB'
<?php
function &getUserEntryByUID($uid) {
    global $config;
    foreach ($config['system']['user'] as &$u) { if ($u['uid'] == $uid) { return $u; } }
    $r = false; return $r;
}
function local_user_set(&$user) { file_put_contents(getenv('LT_CONFIG') . '.set', $user['name']); }
STUB
echo '<?php' > "$work/php/util.inc"
cat > "$work/php/config.json" <<'JSON'
{"trigger_initial_wizard": "", "system": {"user": [{"name": "root", "uid": "0", "password": "$2y$10$default"}]},
 "interfaces": {"wan": {"enable": "1", "if": "mismatch1", "ipaddr": "dhcp", "ipaddrv6": "dhcp6"},
  "lan": {"enable": "1", "if": "mismatch0", "ipaddr": "192.168.1.1", "subnet": "24", "ipaddrv6": "idassoc6",
          "subnetv6": "64", "track6-interface": "wan", "track6-prefix-id": "0"}},
 "dnsmasq": {"enable": "1", "interface": "lan", "dhcp": {"enable_ra": "1"},
  "dhcp_ranges": [{"interface": "lan", "start_addr": "192.168.1.100"}, {"interface": "lan", "start_addr": "::1000"}]}}
JSON
fb=$root/hosts/ansible/bootstrap/opnsense-first-boot.php
for _ in 1 2; do
  LT_CONFIG=$work/php/config.json php -d include_path="$work/php" "$fb" vtnet0 50 10.1.50.1/24 vtnet1 "$work/root.hash" > "$work/php/out" 2>&1 || { cat "$work/php/out"; break; }
done
python3 -I - "$work/php/config.json" "$work/root.hash" <<'PY' && ok "first boot (run twice): one mgmt VLAN, LAN on it with .1/24 and no IPv6, WAN DHCPv4 only, no LAN DHCP or RA, root's hash, no wizard" || bad "the first-boot PHP"
import json, sys
c = json.load(open(sys.argv[1]))
assert [v["vlanif"] for v in c["vlans"]["vlan"]] == ["vtnet0_vlan50"] and c["vlans"]["vlan"][0]["if"] == "vtnet0"
assert c["vlans"]["vlan"][0]["tag"] == "50"
lan, wan = c["interfaces"]["lan"], c["interfaces"]["wan"]
assert lan["if"] == "vtnet0_vlan50" and lan["ipaddr"] == "10.1.50.1" and lan["subnet"] == "24"
assert not {"ipaddrv6", "subnetv6", "track6-interface", "track6-prefix-id"} & set(lan), lan
assert wan["if"] == "vtnet1" and wan["ipaddr"] == "dhcp" and "ipaddrv6" not in wan
assert not [r for r in c["dnsmasq"].get("dhcp_ranges", {}).values() if r["interface"] == "lan"] if isinstance(c["dnsmasq"].get("dhcp_ranges"), dict) \
    else not [r for r in c["dnsmasq"].get("dhcp_ranges", []) if r["interface"] == "lan"]
assert "enable_ra" not in c["dnsmasq"]["dhcp"] and "trigger_initial_wizard" not in c
assert c["system"]["user"][0]["password"] == open(sys.argv[2]).read().strip()
PY
for bad_args in "vtnet0 50 10.1.50.1/24 vtnet0" "vtnet0 5000 10.1.50.1/24 vtnet1" "vtnet0 50 10.1.50.1 vtnet1"; do
  # shellcheck disable=SC2086
  if LT_CONFIG=$work/php/config.json php -d include_path="$work/php" "$fb" $bad_args "$work/root.hash" > /dev/null 2>&1; then
    bad "the first-boot PHP took: $bad_args"
  else
    ok "the first-boot PHP refuses: $bad_args"
  fi
done
echo plain > "$work/php/plain.hash"
LT_CONFIG=$work/php/config.json php -d include_path="$work/php" "$fb" vtnet0 50 10.1.50.1/24 vtnet1 "$work/php/plain.hash" > /dev/null 2>&1 \
  && bad "the first-boot PHP took a root hash that is not SHA-512 crypt" || ok "the first-boot PHP refuses a root hash that is not SHA-512 crypt"

# The role takes the binary out of a .deb (an ar archive holding data.tar.xz) with Python only.
mkdir -p "$work/deb/usr/bin"
printf '#!/bin/sh\necho example\n' > "$work/deb/usr/bin/proxmox-auto-install-assistant"
tar -C "$work/deb" -cJf "$work/data.tar.xz" ./usr/bin/proxmox-auto-install-assistant
echo 2.0 > "$work/debian-binary"
python3 -I - "$work" <<'PY'
import os, sys
d = sys.argv[1]
with open(os.path.join(d, "example.deb"), "wb") as out:
    out.write(b"!<arch>\n")
    for name in ("debian-binary", "control.tar.xz", "data.tar.xz"):
        body = open(os.path.join(d, name), "rb").read() if name != "control.tar.xz" else b"x" * 3
        out.write(f"{name + '/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(body):<10}`\n".encode())
        out.write(body + (b"\n" if len(body) % 2 else b""))
PY
python3 -I - "$role/tasks/lab_test.yml" > "$work/extract.py" <<'PY'
import sys, yaml
t = [x for x in yaml.safe_load(open(sys.argv[1])) if "ansible.builtin.command" in x][0]
print(t["ansible.builtin.command"]["argv"][3])
PY
python3 -I "$work/extract.py" "$work/example.deb" "$work/out" \
  && cmp -s "$work/out" "$work/deb/usr/bin/proxmox-auto-install-assistant" \
  && ok "the role's unpacking takes the assistant out of a .deb" || bad "the role's unpacking"

[ "$fails" -eq 0 ] && echo "lab-test: all checks passed" || { echo "lab-test: $fails failed"; exit 1; }
