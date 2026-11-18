#!/usr/bin/env bash
# The lab-test wrapper's helper (lab-test-answer.py), its pins and refusals, and the role's unpacking of the
# assistant, offline. Made-up values. Needs: python3 3.11 or newer (tomllib) with PyYAML, xz.
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
grep -Eq '^  - name: lab-test$' "$role/defaults/main.yml" && grep -A1 '^  - name: lab-test$' "$role/defaults/main.yml" | grep -q 'args: \[plan, apply, check, destroy, log\]' \
  && ok "the wrapper list allows plan, apply, check, destroy and log" || bad "the wrapper's sudo arguments"

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
