#!/bin/bash
# /usr/local/libexec/agent-box/dev-worker-address.sh: the one address that lets dev's worker reach the Proxmox host's backup
# sftp, handed from the keys user's side of the box to the two jobs that must let it in (the firewall job's rule, the host
# job's reader key). Root owns it. The address is private (it is never printed, never put on a command line):
#   dev-worker-address.sh write    as keys: the first k8s_workers address of the box's dev inventory goes to the handoff file,
#                                  atomically (a temp file in the same folder, then mv). Dev's addresses are static (cloud-init,
#                                  dev-vms.tfvars, and rebuild.sh refuses an inventory host that is not one of them), so the file
#                                  follows the inventory and not the VMs: rebuild.sh calls it each time it parses the inventory, and a
#                                  teardown keeps it. Any refusal (not exactly one worker, not one dev node address) removes the file.
#   dev-worker-address.sh remove   as keys: the file is removed (by hand, when dev is given up).
#   dev-worker-address.sh read     as hostops or guardops (group devaddr): the address on stdout, so a caller captures it; nothing
#                                  and exit 0 when the file is missing; exit 1, naming no value, when it is not exactly one
#                                  IPv4 address of the dev VLAN's node range (10.1.30.1 to .223, standard 0002).
#   dev-worker-address.sh key      as keys: dev's worker needs a key of its own on the Proxmox host (the carry of #775, with nothing to carry
#                                  off a node). It makes the pair once, in <keys>/dev/backup-sftp/<worker>.key and .pub (never over an
#                                  existing pair), hands the public half (one ed25519 line) to dev-worker-backup.pub in the handoff folder,
#                                  and, when hostops has published the Proxmox host's public host key (host-key folder, below), writes
#                                  <worker>.known_hosts beside the pair, the pinned key the restore play reads. Public data only goes out.
#   dev-worker-address.sh read-key as hostops (group devaddr): that one public key line on stdout, nothing for no file, refusal (no value)
#                                  for anything that is not exactly one ssh-ed25519 line.
# The file is keys:devaddr, mode 0640, in a folder keys:devaddr mode 0750; it holds one line, one address, nothing else.
# Exit codes: 0 done, 1 refused, 2 usage.
set -euo pipefail
umask 027
work=/var/lib/agent-box
handoff=/var/lib/agent-box-handoff
file=$handoff/dev-worker-address
keyfile=$handoff/dev-worker-backup.pub
keys=/etc/agent-keys
hostkey_file=/var/lib/agent-box-hostkey/proxmox-host.pub   # written by proxmox-host.sh (hostops): the host's public host key, two fields
group=devaddr
inventory=$work/rebuild-dev/inventory
libexec=/usr/local/libexec/agent-box
export PATH=$libexec/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin

usage() { echo "usage: dev-worker-address.sh write|remove|read|key|read-key" >&2; exit 2; }
[[ $# -eq 1 ]] || usage

# One IPv4 address of the dev nodes' range, from stdin; the address on stdout, or nothing and exit 1. No value is printed on failure.
check_shape() {
  python3 -I -c '
import ipaddress, sys
raw = sys.stdin.read()
lines = raw.split("\n")
if len(lines) != 2 or lines[1] != "":
    sys.exit(1)
try:
    ip = ipaddress.IPv4Address(lines[0])
except ValueError:
    sys.exit(1)
if str(ip) != lines[0] or ip not in ipaddress.ip_network("10.1.30.0/24") or not 1 <= int(ip) % 256 <= 223:
    sys.exit(1)
sys.stdout.write(lines[0] + "\n")'
}

# One line "ssh-ed25519 <base64>", from stdin; the line on stdout or nothing and exit 1. A comment field is dropped, so only the two fields pass.
check_pub() {
  python3 -I -c '
import re, sys
raw = sys.stdin.read()
lines = raw.split("\n")
if len(lines) != 2 or lines[1] != "":
    sys.exit(1)
f = lines[0].split(" ")
if len(f) < 2 or f[0] != "ssh-ed25519" or not re.fullmatch(r"AAAAC3NzaC1lZDI1NTE5[A-Za-z0-9+/]{48}", f[1]):
    sys.exit(1)
sys.stdout.write(f[0] + " " + f[1] + "\n")'
}

worker_name() { # the one k8s_workers inventory name, or nothing and exit 1
  ansible-inventory -i "$inventory/" --list | python3 -I -c '
import json, re, sys
h = json.load(sys.stdin).get("k8s_workers", {}).get("hosts", [])
if len(h) != 1 or not re.fullmatch(r"[a-z0-9]([a-z0-9-]*[a-z0-9])?", h[0]):
    sys.exit(1)
sys.stdout.write(h[0] + "\n")'
}

case $1 in
  read-key)
    [[ -e $keyfile ]] || exit 0
    [[ -r $keyfile ]] || { echo "dev-worker-address: the backup key file is there but this user can't read it" >&2; exit 1; }
    out=$(check_pub < "$keyfile") && [[ $out == "$(cat "$keyfile")" ]] \
      || { echo "dev-worker-address: the backup key file is not exactly one ssh-ed25519 line (two fields, no comment); refusing" >&2; exit 1; }
    printf '%s\n' "$out" ;;
  key)
    [[ -d $handoff ]] || { echo "dev-worker-address: $handoff is missing (the agent_box role makes it)" >&2; exit 1; }
    w=$(worker_name) || { rm -f -- "$keyfile"; echo "dev-worker-address: the dev inventory does not have exactly one k8s_workers host; no backup key" >&2; exit 1; }
    kd=$keys/dev/backup-sftp
    install -d -m 0700 "$kd"
    if [[ ! -e $kd/$w.key || ! -e $kd/$w.pub ]]; then
      rm -f -- "$kd/$w.key.part" "$kd/$w.key.part.pub"
      ssh-keygen -q -t ed25519 -N '' -C "c1restore@$w" -f "$kd/$w.key.part"
      chmod 600 "$kd/$w.key.part" "$kd/$w.key.part.pub"
      mv -f -- "$kd/$w.key.part.pub" "$kd/$w.pub"
      mv -f -- "$kd/$w.key.part" "$kd/$w.key"
    fi
    pub=$(check_pub < "$kd/$w.pub") || { echo "dev-worker-address: the carried public key is not one ssh-ed25519 line" >&2; exit 1; }
    printf '%s\n' "$pub" > "$keyfile.part"
    chgrp "$group" "$keyfile.part"
    chmod 0640 "$keyfile.part"
    mv -f -- "$keyfile.part" "$keyfile"
    if [[ -r $hostkey_file ]] && hk=$(check_pub < "$hostkey_file" 2>/dev/null); then
      printf 'c1-backup-target %s\n' "$hk" > "$kd/$w.known_hosts.part"
      chmod 600 "$kd/$w.known_hosts.part"
      mv -f -- "$kd/$w.known_hosts.part" "$kd/$w.known_hosts"
    fi
    echo "dev-worker-address: the worker's backup key is in place (public half handed over, nothing else shown)" ;;
  read)
    [[ -e $file ]] || exit 0
    [[ -r $file ]] || { echo "dev-worker-address: the handoff file is there but this user can't read it" >&2; exit 1; }
    out=$(check_shape < "$file") || { echo "dev-worker-address: the handoff file is not exactly one dev node address; refusing" >&2; exit 1; }
    printf '%s\n' "$out" ;;
  remove)
    rm -f -- "$file" "$file".part ;;
  write)
    [[ -d $handoff ]] || { echo "dev-worker-address: $handoff is missing (the agent_box role makes it)" >&2; exit 1; }
    addr=$(ansible-inventory -i "$inventory/" --list | python3 -I -c '
import json, sys
inv = json.load(sys.stdin)
hosts = inv.get("k8s_workers", {}).get("hosts", [])
hv = inv.get("_meta", {}).get("hostvars", {})
if len(hosts) != 1:
    sys.exit(1)
sys.stdout.write(str(hv.get(hosts[0], {}).get("ansible_host", "")) + "\n")') \
      || { rm -f -- "$file"; echo "dev-worker-address: the dev inventory does not have exactly one k8s_workers host; no handoff file" >&2; exit 1; }
    addr=$(printf '%s\n' "$addr" | check_shape) \
      || { rm -f -- "$file"; echo "dev-worker-address: the worker's address is not one dev node address; no handoff file" >&2; exit 1; }
    tmp=$file.part
    printf '%s\n' "$addr" > "$tmp"
    chgrp "$group" "$tmp"
    chmod 0640 "$tmp"
    mv -f -- "$tmp" "$file"
    echo "dev-worker-address: handoff file written (one address, not shown)" ;;
  *) usage ;;
esac
