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
grep -Eq '^  - name: lab-test$' "$role/defaults/main.yml" && grep -A1 '^  - name: lab-test$' "$role/defaults/main.yml" | grep -q 'args: \[plan, apply, check, host, lab, firstboot, opnsense, wancheck, connector, safety, prove, destroy, log\]' \
  && ok "the wrapper list allows every step, safety, prove, destroy and log" || bad "the wrapper's sudo arguments"

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
python3 -I - "$w" "$work/hosts.yml" "$root/hosts/ansible/roles/tailnet_connector/meta/argument_specs.yml" <<'PY' && ok "connector: the runbook's install lines, never joined, tailnet-connector.yml twice with changed=0, the route and gateway checked" || bad "connector's wiring"
import sys, yaml
t = open(sys.argv[1]).read()
h = yaml.safe_load(open(sys.argv[2]))["all"]["children"]["proxmox"]["hosts"]["proxmox_host"]
assert h["tailnet_connector_extra_routes"] == ["10.1.30.198/32"] and h["tailnet_connector_lab_supernet"] == "10.1.0.0/16"
opts = yaml.safe_load(open(sys.argv[3]))["argument_specs"]["main"]["options"]
assert {k for k, v in opts.items() if v.get("required")} - set(h) == {"lab_vlans"}
f = t[t.index("\nconnector() {"):]
f = f[:f.index("\n}\n")]
# Never joined: no auth key, no tailscale up or login anywhere in the wrapper; stop before anything when logged in.
assert "tailscale up" not in t and "auth-key" not in t and "tailscale login" not in t
assert f.index('[[ $state != Running && $state != Starting ]]') < f.index("vm 'bash -s'")
assert f.rindex("[[ $state == NeedsLogin ]]") > f.index("playbooks/tailnet-connector.yml")
for line in ["https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg", "https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list",
             "apt-get install -y tailscale", "systemctl is-enabled tailscaled)\" = enabled", "/etc/sysctl.d/99-tailscale.conf"]:
    assert line in f, line
rb = open(sys.argv[1].replace("hosts/ansible/roles/agent_box/files/lab-test.sh", "docs/runbooks/set-up-tailnet-client-in-ct-900.md")).read()
for line in ["https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg", "apt-get install -y tailscale",
             'printf "net.ipv4.ip_forward = 1\\nnet.ipv6.conf.all.forwarding = 1\\n" > /etc/sysctl.d/99-tailscale.conf']:
    assert line in rb and line in f, line
assert "for n in 1 2; do" in f and "changed=0 +unreachable=0 +failed=0' \"$files/connector-run.log\"" in f
assert "grep -q 'via $gw dev eth1'" in f and "ping -c 1 -W 2 -I eth1 $gw" in f
PY
# safety: the firewall tag off, then on twice, the third run changed=0, the timer cancelled; the copy's home LAN is dev.
python3 -I - "$w" "$work/hosts.yml" "$role/../proxmox_firewall/meta/argument_specs.yml" <<'PY' && ok "safety: the firewall off, then on with the dead-man timer, then no change; dev as the copy's home LAN" || bad "safety's wiring"
import sys, yaml
t = open(sys.argv[1]).read()
h = yaml.safe_load(open(sys.argv[2]))["all"]["children"]["proxmox"]["hosts"]["proxmox_host"]
assert h["proxmox_firewall_home_lan_cidr"] == "10.1.30.0/24"
opts = yaml.safe_load(open(sys.argv[3]))["argument_specs"]["main"]["options"]
assert {k for k, v in opts.items() if v.get("required")} - set(h) <= {"lab_vlans"}
f = t[t.index("\nsafety() {"):]
f = f[:f.index("\n}\n")]
assert "for n in 1 2 3; do" in f and "(( n == 1 )) || extra=(-e '{\"proxmox_firewall_enable\": true}')" in f
assert "playbooks/proxmox-safety.yml --tags firewall" in f and "--tags notify" not in f and "--tags backup" not in f
assert "changed=0 +unreachable=0 +failed=0' \"$files/safety-run.log\"" in f
assert "pve-firewall status' | grep -q 'enabled/running'" in f and "systemctl is-active --quiet central-hub-fw-deadman.timer" in f
PY
# Every playbook the copy's inventory runs checks the arguments of every role it lists, tagged always, whatever the
# --tags: each required input of each of those roles must be in the inventory (hosts.yml, plus the VLAN file the
# wrapper copies into its group_vars), or the run fails at its first task.
python3 -I - "$work/hosts.yml" "$root/hosts/ansible" "$vlans" "$w" <<'PY' && ok "the copy's inventory holds every required input of every role in proxmox-host.yml, tailnet-connector.yml and proxmox-safety.yml" || bad "a role's required input is missing from the copy's inventory"
import os, sys, yaml
h = yaml.safe_load(open(sys.argv[1]))["all"]["children"]["proxmox"]["hosts"]["proxmox_host"]
assert 'cp "$vlans" "$files/inventory/group_vars/all/vlans.yml"' in open(sys.argv[4]).read()
have = set(h) | set(yaml.safe_load(open(sys.argv[3])))
base, missing, seen = sys.argv[2], [], []
for pb in ("proxmox-host.yml", "tailnet-connector.yml", "proxmox-safety.yml"):
    for play in yaml.safe_load(open(os.path.join(base, "playbooks", pb))):
        for r in play.get("roles", []):
            name = r["role"] if isinstance(r, dict) else r
            seen.append(name)
            spec = os.path.join(base, "roles", name, "meta", "argument_specs.yml")
            if not os.path.isfile(spec):
                continue
            for ep in yaml.safe_load(open(spec))["argument_specs"].values():
                need = {k for k, v in (ep.get("options") or {}).items() if v.get("required")}
                missing += [f"{pb} {name} {k}" for k in sorted(need - have)]
assert {"proxmox_network", "tailnet_connector", "proxmox_notify", "proxmox_backup", "proxmox_firewall"} <= set(seen), seen
assert not missing, missing
assert h["proxmox_backup_disk"].startswith("/dev/disk/by-id/lab-test-copy-")
PY
# prove: run against a stand-in wrapper that logs each step and fails where told; then the child check on its own.
body=$(sed -n '/^prove() {$/,/^}$/p' "$w")
cat > "$work/prove-step.sh" <<'SH'
#!/bin/bash
echo "$1 parent=${LAB_TEST_PROVE_PARENT:-}" >> "$PROVE_CALLS"
[[ $1 != "${PROVE_FAIL_AT:-}" ]]
SH
chmod +x "$work/prove-step.sh"
prove_run() { # fail-at
  : > "$work/prove-calls"
  PROVE_CALLS=$work/prove-calls PROVE_FAIL_AT=$1 VMID=256 bash -c "set -euo pipefail; $body"$'\n'"set -- ; prove" "$work/prove-step.sh" > "$work/prove-out" 2>&1
}
pid_ok() { awk '{print $2}' "$work/prove-calls" | grep -vx 'parent=[0-9]\+' | grep -q . && return 1; return 0; }
if prove_run "" && [[ $(awk '{print $1}' "$work/prove-calls" | paste -sd' ') == "plan apply check host lab firstboot opnsense wancheck connector safety destroy" ]] \
  && pid_ok && grep -q 'every step passed, build to destroy' "$work/prove-out"; then
  ok "prove runs plan through safety in order, then destroy, each as a child that names its parent"
else
  bad "prove's order"; cat "$work/prove-calls" "$work/prove-out"
fi
if ! prove_run lab && [[ $(awk '{print $1}' "$work/prove-calls" | paste -sd' ') == "plan apply check host lab destroy" ]] \
  && grep -q 'stopped at lab; the copy is destroyed' "$work/prove-out"; then
  ok "prove stops at the first failed step, still destroys, and fails"
else
  bad "prove after a failed step"; cat "$work/prove-calls" "$work/prove-out"
fi
if ! prove_run destroy && grep -q 'destroy failed (exit 1); VM 256 may still exist' "$work/prove-out"; then
  ok "prove fails loudly when destroy fails"
else
  bad "prove after a failed destroy"; cat "$work/prove-out"
fi
childblock=$(sed -n '/^child=0$/,/^unset LAB_TEST_PROVE_PARENT$/p' "$w")
child_of() { # LAB_TEST_PROVE_PARENT value ("parent" for the run's own parent), action
  bash -c 'if [[ $1 == parent ]]; then export LAB_TEST_PROVE_PARENT=$PPID; else export LAB_TEST_PROVE_PARENT=$1; fi; action=$2
'"$childblock"'
echo "$child ${LAB_TEST_PROVE_PARENT:-unset}"' _ "$1" "$2"
}
[[ $(child_of parent lab) == "1 unset" && $(child_of 1 lab) == "0 unset" && $(child_of parent prove) == "0 unset" && $(child_of "" lab) == "0 unset" ]] \
  && ok "a run is prove's step only when its parent named itself, never for prove, and the name does not pass on" \
  || bad "the prove child check"
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
python3 -I - "$w" "$work/layers" <<'PY' && ok "wancheck: the copy's WAN on its own portless vmbr9, the console check before link-up, the watch at link-up and over a reboot, WAN down on any failure" || bad "wancheck's wiring"
import json, os, sys
t = open(sys.argv[1]).read()
assert json.load(open(os.path.join(sys.argv[2], "firewall.tfvars.json")))["wan_bridge"] == "vmbr9"
lab = t[t.index("\nlab() {"):]
lab = lab[:lab.index("\n}\n")]
assert lab.index('pvesh create "/nodes/$n/network" --iface vmbr9 --type bridge') < lab.index("for f in network firewall remote-access")
f = t[t.index("\nwancheck() {"):]
f = f[:f.index("\n}\n")]
pre = f.index('pgrep -lf \\"dhclient.*vtnet1\\"", "! pgrep -lf \\"radvd|kea-dhcp|dhcp6c\\""')
up = f.index("wan_link true")
assert pre < f.index('"$console_py"') < up < f.index("vm 'qm reboot 100'")
assert f.index("wan_watch 120 & watcher=$!") < up and 'vm "python3 -I - vmbr9 $wanmac $*" < "$wan_watch_py"' in f
# Over the reboot, only frames from VM 100's new WAN tap count (net1 is tap100i1).
assert f.index("wan_watch 240 tap100i1 & watcher=$!") < f.index("vm 'qm reboot 100'")
assert f.count("wan_link false; return 1") == 2 and f.count('wait "$watcher" ||') == 2
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
grep -q '"$files"/opnsense-api.\* "$files"/opnsense-ssh.\* "$files/opnsense-run.log"' "$w" \
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

# Step 6's SSH for root on VM 100: the box makes the key for the copy and sends only its public line; firstboot and the
# opnsense step check SSH by that key; destroy removes it.
python3 -I - "$w" <<'PY' && ok "firstboot makes the copy's SSH key on the box and sends VM 100 only its public line" || bad "firstboot's SSH key wiring"
import re, sys
t = open(sys.argv[1]).read()
assert 'ssh-keygen -q -t ed25519 -N "" -C lab-test-vm100 -f "$files/opnsense-ssh.key"' in t
assert '"opnsense-ssh-key.php": sys.argv[8], "root-ssh.pub": sys.argv[9]}' in t
args = re.search(r'"reboot": True\}\)\)\' (.*?)> "\$files/console-plan\.json"', t, re.S).group(1)
assert '"$repo/hosts/ansible/bootstrap/opnsense-ssh-key.php" "$files/opnsense-ssh.key.pub"' in args, args
assert '"$files/opnsense-ssh.key"' not in args and "opnsense-ssh.key " not in args, args
PY
grep -q 'if sshd=$(vm100 /usr/local/sbin/sshd -T); then up=1; break; fi' "$w" \
  && grep -q 'problems=$(sshd_settings_ok "$gw" vtnet1 <<<"$sshd")' "$w" \
  && grep -q 'after opnsense.yml, VM 100 still answers SSH as root by the copy' "$w" \
  && grep -q -- '-o IdentitiesOnly=yes -o BatchMode=yes' "$w" \
  && grep -q '"$files"/opnsense-api\.\* "$files"/opnsense-ssh\.\*' "$w" \
  && ok "firstboot and the opnsense step check SSH by the copy's key with sshd's own settings, and destroy removes the key" \
  || bad "the SSH checks' wiring"
# The SSH key command, as the console runs it: the public line goes whether the script works or fails, and its exit
# code comes through.
sshcmd=$(python3 -I -c 'import re, sys
print(re.search(r"\"(php opnsense-ssh-key\.php root-ssh\.pub;[^\"]*)\"", open(sys.argv[1]).read()).group(1))' "$w")
mkdir -p "$work/sshk/bin"
for want in 0 4; do
  rm -rf "$work/sshk/dir" && mkdir -p "$work/sshk/dir"
  echo 'ssh-ed25519 AAAA x' > "$work/sshk/dir/root-ssh.pub"
  printf '#!/bin/sh\n[ "$1 $2" = "opnsense-ssh-key.php root-ssh.pub" ] && [ -s root-ssh.pub ] || exit 9\nexit %s\n' "$want" > "$work/sshk/bin/php"
  chmod +x "$work/sshk/bin/php"
  got=0; ( cd "$work/sshk/dir" && PATH=$work/sshk/bin:$PATH sh -c "$sshcmd" ) >/dev/null 2>&1 || got=$?
  if [[ $got == "$want" && ! -e $work/sshk/dir/root-ssh.pub ]]; then
    ok "the SSH key command removes the public line, and exits $want when the script does"
  else
    bad "the SSH key command (wanted exit $want, got $got)"
  fi
done
# sshd_settings_ok against `sshd -T` output in OpenSSH's own format (servconf.c, format_listen_addrs): IPv6 in brackets,
# link-local with its scope.
eval "$(sed -n '/^sshd_settings_ok() {/,/^}/p' "$w")"
sshd_good='port 22
permitrootlogin yes
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
listenaddress 10.1.50.1:22
listenaddress 127.0.0.1:22
listenaddress [::1]:22
listenaddress [fe80::1%lo0]:22
listenaddress [fe80::5a9c:fcff:fe00:1%vtnet0_vlan50]:22'
sshd_settings_ok 10.1.50.1 vtnet1 <<<"$sshd_good" >/dev/null \
  && ok "the sshd check passes root by key on the mgmt gateway, loopback and LAN link-local only" \
  || bad "the sshd check refused good settings"
while IFS='|' read -r what from to; do
  if out=$(sshd_settings_ok 10.1.50.1 vtnet1 <<<"${sshd_good/"$from"/"$to"}"); then
    bad "the sshd check passed $what"
  else
    ok "the sshd check refuses $what ($out)"
  fi
done <<'CASES'
a WAN listen address|listenaddress 127.0.0.1:22|listenaddress 192.0.2.10:22
every address|listenaddress 127.0.0.1:22|listenaddress 0.0.0.0:22
a WAN link-local address|%vtnet0_vlan50]|%vtnet1]
an unscoped link-local address|%vtnet0_vlan50]|]
no mgmt gateway|listenaddress 10.1.50.1:22|listenaddress 127.0.0.2:22
password sign-in|passwordauthentication no|passwordauthentication yes
keyboard-interactive sign-in|kbdinteractiveauthentication no|kbdinteractiveauthentication yes
no root|permitrootlogin yes|permitrootlogin no
no keys|pubkeyauthentication yes|pubkeyauthentication no
CASES

# wancheck's capture: the watch's frames and its sorting, offline; then, where this runs as root or with sudo, the whole
# watch on a made-up bridge against a fake WAN that is a client only, a DHCPv4 server, an IPv6 router, or silent.
wan_watch=$files/lab-test-wan-watch.py
python3 -I - "$wan_watch" <<'PY' && ok "the WAN watch's probes carry valid checksums, and it sorts server-type frames from the WAN's MAC only" || bad "the WAN watch's frames"
import importlib.util, socket, struct, sys
sp = importlib.util.spec_from_file_location("w", sys.argv[1]); w = importlib.util.module_from_spec(sp); sp.loader.exec_module(w)
d4, rs, sol = w.probes()
assert w.csum(d4[14:34]) == 0 and d4[0:6] == b"\xff" * 6 and d4[6:12] == w.PROBE_MAC
assert struct.unpack("!HH", d4[34:38]) == (68, 67) and d4[34 + 8 + 236:34 + 8 + 240] == b"\x63\x82\x53\x63"
for f, nh in ((rs, 58), (sol, 17)):
    ip6 = f[14:]
    plen = struct.unpack("!H", ip6[4:6])[0]
    assert ip6[6] == nh and len(ip6) == 40 + plen
    pseudo = ip6[8:24] + ip6[24:40] + struct.pack("!I3xB", plen, nh)
    assert w.csum(pseudo + ip6[40:]) == 0, nh
assert rs[54] == 133 and struct.unpack("!HH", sol[54:58]) == (546, 547) and sol[62] == 1
wan = bytes.fromhex("020000000101")
def eth(src, etype, body): return b"\xff" * 6 + src + struct.pack("!H", etype) + body
ip4 = lambda sport: bytes([0x45]) + b"\0" * 8 + bytes([17]) + b"\0" * 10 + struct.pack("!HH", sport, 68)
assert w.classify(eth(wan, 0x0800, ip4(67)), wan) == "dhcp4-server"
assert w.classify(eth(wan, 0x0800, ip4(68)), wan) == "other"
assert w.classify(eth(b"\x02" * 6, 0x0800, ip4(67)), wan) is None
assert w.classify(eth(wan, 0x8100, b"\0\x0a\x08\x00" + ip4(67)), wan) == "dhcp4-server"
ip6 = lambda nh, body: b"\x60\0\0\0" + struct.pack("!H", len(body)) + bytes([nh, 255]) + b"\0" * 32 + body
assert w.classify(eth(wan, 0x86DD, ip6(58, bytes([134, 0, 0, 0]))), wan) == "ra"
assert w.classify(eth(wan, 0x86DD, ip6(58, bytes([135, 0, 0, 0]))), wan) == "other"
assert w.classify(eth(wan, 0x86DD, ip6(17, struct.pack("!HH", 547, 546))), wan) == "dhcp6-server"
PY
sudo=()
if [[ $(id -u) != 0 ]]; then
  if sudo -n true 2>/dev/null; then sudo=(sudo -n); else sudo=(none); fi
fi
if [[ ${sudo[0]-} == none ]]; then
  echo "skip - the live WAN watch needs root or sudo"
else
  cat > "$work/fakewan.py" <<'PY'
import importlib.util, socket, struct, sys, time
sp = importlib.util.spec_from_file_location("w", sys.argv[1]); w = importlib.util.module_from_spec(sp); sp.loader.exec_module(w)
mode, secs, wan = sys.argv[2], float(sys.argv[3]), bytes.fromhex("020000000101")
s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3)); s.bind(("ltwan0", 0)); s.settimeout(0.2)
def udp4(sport, dport):
    udp = struct.pack("!HHHH", sport, dport, 12, 0) + b"test"
    ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(udp), 0, 0, 64, 17, 0, b"\0" * 4, b"\xff" * 4)
    return b"\xff" * 6 + wan + b"\x08\x00" + ip[:10] + struct.pack("!H", w.csum(ip)) + ip[12:] + udp
def ra():
    body = w.ipv6(w.link_local(wan), socket.inet_pton(socket.AF_INET6, "ff02::1"), 58, bytes([134, 0, 0, 0]) + b"\0" * 12)
    return b"\x33\x33\0\0\0\1" + wan + b"\x86\xdd" + body
end, nxt = time.time() + secs, 0
while time.time() < end:
    if mode != "silent" and time.time() >= nxt:
        s.send(udp4(68, 67)); nxt = time.time() + 2   # a DHCP client's discover, as dhclient sends
    try:
        f = s.recv(2048)
    except socket.timeout:
        continue
    if f[6:12] != w.PROBE_MAC:
        continue
    if mode == "server" and f[12:14] == b"\x08\x00":
        s.send(udp4(67, 68))
    if mode == "router" and f[12:14] == b"\x86\xdd" and f[20] == 58:
        s.send(ra())
PY
  # The fake WAN is a host link, and with IPv6 on, Linux keeps sending router solicitations from its MAC with backoff
  # and no end (MAX_RTR_SOLICITATIONS is -1), so one can land in the silent run's window and count as a frame.
  # IPv6 off on ltwan0 leaves only the frames fakewan.py sends. veth makes it, here and again for each reboot case.
  veth() { "${sudo[@]}" ip link add ltwan0 type veth peer name ltwan0br && "${sudo[@]}" ip link set ltwan0br master vmbr97 \
    && { [[ ! -e /proc/sys/net/ipv6/conf/ltwan0 ]] || "${sudo[@]}" sysctl -qw net.ipv6.conf.ltwan0.disable_ipv6=1; } \
    && "${sudo[@]}" ip link set ltwan0 address 02:00:00:00:01:01 && "${sudo[@]}" ip link set ltwan0br up && "${sudo[@]}" ip link set ltwan0 up; }
  "${sudo[@]}" ip link add vmbr97 type bridge && "${sudo[@]}" ip link set vmbr97 up && veth
  for want in client:0 server:3 router:3 silent:4; do
    mode=${want%:*}; rc=0
    "${sudo[@]}" python3 -I "$work/fakewan.py" "$wan_watch" "$mode" 14 & fake=$!
    sleep 0.5
    "${sudo[@]}" python3 -I "$wan_watch" vmbr97 02:00:00:00:01:01 12 > "$work/watch.out" 2>&1 || rc=$?
    wait "$fake" || true
    if [[ $rc == "${want#*:}" ]]; then ok "the live WAN watch exits $rc for a WAN that is $mode: $(head -1 "$work/watch.out")"
    else bad "the live WAN watch for a $mode WAN (exit $rc)"; cat "$work/watch.out"; fi
  done
  # Over a reboot (a port named): frames count only once the port is a new device. Phase 1 runs the fake on the first
  # veth; then the veth is deleted and made again under the same name, as a reboot gives VM 100 a new tap; phase 2
  # runs the fake again, or not at all.
  for want in before-only:4 before-and-after:0 never-cycled:5; do
    mode=${want%:*}; rc=0
    "${sudo[@]}" python3 -I "$wan_watch" vmbr97 02:00:00:00:01:01 14 ltwan0br > "$work/watch.out" 2>&1 & watch=$!
    sleep 0.5
    "${sudo[@]}" python3 -I "$work/fakewan.py" "$wan_watch" client 4 || true
    if [[ $mode != never-cycled ]]; then
      "${sudo[@]}" ip link del ltwan0 && veth
      [[ $mode == before-only ]] || "${sudo[@]}" python3 -I "$work/fakewan.py" "$wan_watch" client 4 || true
    fi
    wait "$watch" || rc=$?
    if [[ $rc == "${want#*:}" ]]; then ok "the live WAN watch over a reboot exits $rc for frames $mode: $(head -2 "$work/watch.out" | tail -1)"
    else bad "the live WAN watch over a reboot, frames $mode (exit $rc)"; cat "$work/watch.out"; fi
  done
  python3 -I "$wan_watch" vmbr97 02:00:00:00:01:01 1 ltwan9 > "$work/watch.out" 2>&1 && bad "the watch took a port not on the bridge" \
    || { grep -q 'is not on vmbr97 at the start' "$work/watch.out" && ok "the watch refuses a port that is not on the bridge at the start" || bad "the watch's missing-port message"; }
  "${sudo[@]}" ip link del ltwan0 || true; "${sudo[@]}" ip link del vmbr97 || true
fi

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

# The SSH key PHP against the same stubs, run twice: SSH on, root by key, password sign-in and the installer fallback
# off, LAN only, root's keys that one line; anything but one ed25519 line is refused and changes nothing.
sshphp=$root/hosts/ansible/bootstrap/opnsense-ssh-key.php
cat > "$work/php/ssh.json" <<'JSON'
{"system": {"ssh": {"group": "admins", "passwordauth": "1", "noauto": "1", "interfaces": "wan"},
 "user": [{"name": "x", "uid": "2000"}, {"name": "root", "uid": "0", "authorizedkeys": "b2xk"}]}}
JSON
ssh-keygen -q -t ed25519 -N "" -C lab-test-vm100 -f "$work/php/k"
rm -f "$work/php/ssh.json.set"
for _ in 1 2; do
  LT_CONFIG=$work/php/ssh.json php -d include_path="$work/php" "$sshphp" "$work/php/k.pub" > "$work/php/out" 2>&1 || { cat "$work/php/out"; break; }
done
python3 -I - "$work/php/ssh.json" "$work/php/k.pub" <<'PY' && [[ $(cat "$work/php/ssh.json.set") == root ]] \
  && ok "the SSH key PHP (run twice): SSH on for root by key only, LAN only, root's keys that one line" || bad "the SSH key PHP"
import base64, json, sys
c = json.load(open(sys.argv[1]))
assert c["system"]["ssh"] == {"group": "admins", "enabled": "enabled", "permitrootlogin": "1", "interfaces": "lan"}, c["system"]["ssh"]
u = {x["name"]: x for x in c["system"]["user"]}
assert base64.b64decode(u["root"]["authorizedkeys"]).decode() == open(sys.argv[2]).read().strip()
assert "authorizedkeys" not in u["x"]
PY
ssh-keygen -q -t rsa -b 2048 -N "" -f "$work/php/rsa"
cat "$work/php/k.pub" "$work/php/k.pub" > "$work/php/two.pub"
: > "$work/php/empty.pub"
sed 's/ lab-test-vm100$/ x;reboot/' "$work/php/k.pub" > "$work/php/shell.pub"
cp "$work/php/ssh.json" "$work/php/ssh.before"
for f in rsa.pub two.pub empty.pub shell.pub missing.pub; do
  if LT_CONFIG=$work/php/ssh.json php -d include_path="$work/php" "$sshphp" "$work/php/$f" > /dev/null 2>&1 \
      || ! cmp -s "$work/php/ssh.json" "$work/php/ssh.before"; then
    bad "the SSH key PHP took $f"
  else
    ok "the SSH key PHP refuses $f and changes nothing"
  fi
done

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

# node_name: the settings' proxmox_node_name when set, else the one node GET /nodes shows, else a refusal.
sed -n '/^node_name() {/,/^}/p' "$w" > "$work/node_name.sh"
nn_run() { # settings-json nodes-json
  printf '%s\n' "$1" > "$work/nn-settings.json"; nodes_json=$2
  # shellcheck disable=SC2034,SC2329,SC1091
  ( settings=$work/nn-settings.json; px_api() { printf '%s\n' "$nodes_json"; }; . "$work/node_name.sh"; node_name ) 2>&1
}
[ "$(nn_run '{"proxmox_node_name": "setnode1"}' '{"data": [{"node": "apinode1"}]}')" = setnode1 ] \
  && ok "node_name keeps a node the settings name" || bad "node_name with a settings node"
[ "$(nn_run '{"name": "x"}' '{"data": [{"node": "apinode1"}]}')" = apinode1 ] \
  && ok "node_name reads the only node from GET /nodes when the settings name none" || bad "node_name from the API"
out=$(nn_run '{"name": "x"}' '{"data": [{"node": "a1"}, {"node": "b1"}]}') && bad "node_name accepted two nodes" \
  || { grep -q 'shows 2 nodes' <<<"$out" && ok "node_name refuses two nodes" || bad "node_name two-node message: $out"; }
out=$(nn_run '{"name": "x"}' '{"data": [{"node": "bad node"}]}') && bad "node_name accepted a node with a space" || ok "node_name refuses a node name that is not plain"

[ "$fails" -eq 0 ] && echo "lab-test: all checks passed" || { echo "lab-test: $fails failed"; exit 1; }
