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
#   dev-worker-address.sh box-key  as keys: the box's own key for the Proxmox host's backup store (the OPNsense configuration copy and the
#                                  secrets bundle go there, not to Azure). Same shape as `key`: the pair once, in <keys>/box-backup/id_ed25519
#                                  and .pub (never over an existing pair), the public half (one ed25519 line) to box-backup.pub in the handoff
#                                  folder, and, when hostops has published the host's public host key, <keys>/box-backup/known_hosts.
#                                  It also hands over the address the box's own traffic to the Proxmox host's backup store comes from (the box's
#                                  source address toward the host's mgmt address, read from the box's prod inventory copy): box-backup-address, one
#                                  address of the dev VLAN's node range like dev-worker-address. A route that does not go through the firewall
#                                  (the lifeline) gives an address outside that range: refused, with no file and no value printed.
#                                  It also writes the ssh config the box's restic uses (<keys>/box-backup/ssh_config: the alias box-backup-target, the
#                                  host's mgmt address, the key, the pinned host key, batch mode); mode 0600, no secret in it.
#   dev-worker-address.sh box-backend-on   as keys: switches the box's two off-box sends (opnsense-offbox.sh, secrets-bundle-offbox.sh) from Azure to
#   dev-worker-address.sh box-backend-off  the host's store, by writing <keys>/box-backup/backend.env (the repository sftp:box-backup-target:/box and
#                                  the ssh config's path), which both scripts read after their settings; off removes it. On refuses until the pair,
#                                  the pinned host key and the ssh config are there.
#   dev-worker-address.sh box-prove  as keys: proves what the box's key can and cannot do on the host's store, with the box's own ssh config, and
#                                  prints ok or FAIL lines (check 3 has two), no address and no key: (1) it signs in over sftp and its folder is /box;
#                                  (2) it writes a test file there, reads it back the same, and removes it; (3) it cannot write to /, and cannot
#                                  open any other folder it can see in /; (4) it cannot read a file outside the chroot (/etc/passwd); (5) a
#                                  command over ssh runs no shell. Exit 0 only when all five hold; 1 if any check fails or the sign-in does not work.
#   dev-worker-address.sh read-box-key as hostops (group devaddr): that one public key line, nothing for no file, refusal for anything else.
#   dev-worker-address.sh read-box-address as hostops or guardops (group devaddr): that address, nothing for no file, refusal for a bad shape.
# The file is keys:devaddr, mode 0640, in a folder keys:devaddr mode 0750; it holds one line, one address, nothing else.
# Exit codes: 0 done, 1 refused, 2 usage.
set -euo pipefail
umask 027
work=/var/lib/agent-box
handoff=/var/lib/agent-box-handoff
file=$handoff/dev-worker-address
keyfile=$handoff/dev-worker-backup.pub
boxkeyfile=$handoff/box-backup.pub
boxaddrfile=$handoff/box-backup-address
keys=/etc/agent-keys
prod_inventory=$keys/prod/inventory-hosts.yml   # the box's copy of the prod inventory; the host's mgmt address is in it
hostkey_file=/var/lib/agent-box-hostkey/proxmox-host.pub   # written by proxmox-host.sh (hostops): the host's public host key, two fields
group=devaddr
inventory=$work/rebuild-dev/inventory
libexec=/usr/local/libexec/agent-box
export PATH=$libexec/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin

usage() { echo "usage: dev-worker-address.sh write|remove|read|key|read-key|box-key|read-box-key|read-box-address|box-backend-on|box-backend-off|box-prove" >&2; exit 2; }
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


# One IPv4 address, from stdin, any range; the address on stdout, or nothing and exit 1.
check_ipv4() {
  python3 -I -c '
import ipaddress, sys
v = sys.stdin.read().strip()
try:
    ip = ipaddress.IPv4Address(v)
except ValueError:
    sys.exit(1)
if str(ip) != v:
    sys.exit(1)
print(v)'
}
# The host's mgmt address (the one the c1 nodes' backups use), from the prod inventory copy; or nothing and exit 1.
host_mgmt_address() {
  ansible-inventory -i "$prod_inventory" --list | python3 -I -c '
import json, sys
inv = json.load(sys.stdin)
hv = inv.get("_meta", {}).get("hostvars", {})
found = {str(v.get("proxmox_host_mgmt_address", "")) for v in hv.values() if v.get("proxmox_host_mgmt_address")}
found |= {str(v) for g in inv.values() if isinstance(g, dict) for k, v in (g.get("vars") or {}).items() if k == "proxmox_host_mgmt_address"}
if len(found) != 1:
    sys.exit(1)
sys.stdout.write(found.pop() + "\n")'
}
# The source address the kernel would use toward an address (a UDP connect sends nothing); the address on stdout.
source_toward() { python3 -I -c 'import socket, sys; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect((sys.argv[1], 22)); print(s.getsockname()[0])' "$1"; }

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
  box-backend-on)
    kd=$keys/box-backup
    for f in id_ed25519 id_ed25519.pub known_hosts ssh_config; do
      [[ -s $kd/$f ]] || { echo "dev-worker-address: $kd/$f is missing; run box-key (and a host job, which publishes the host's key) first; the Azure send stays" >&2; exit 1; }
    done
    printf 'RESTIC_REPOSITORY=sftp:box-backup-target:/box\nOFFBOX_RESTIC_SSH_CONFIG=%s\n' "$kd/ssh_config" > "$kd/backend.env.part"
    chmod 600 "$kd/backend.env.part"
    mv -f -- "$kd/backend.env.part" "$kd/backend.env"
    echo "dev-worker-address: the box's off-box sends now go to the Proxmox host's store" ;;
  box-backend-off)
    rm -f -- "$keys/box-backup/backend.env" "$keys/box-backup/backend.env.part"
    echo "dev-worker-address: the box's off-box sends are back on the settings' repository (Azure)" ;;
  box-prove)
    kd=$keys/box-backup
    cfg=$kd/ssh_config
    [[ -r $cfg && -r $kd/id_ed25519 && -s $kd/known_hosts ]] || { echo "dev-worker-address: box-prove needs the ssh config, the key and the pinned host key (run box-key and a host job first)" >&2; exit 1; }
    name=boxprove-$$.tmp
    tdir=$(mktemp -d)
    trap 'rm -rf -- "$tdir"' EXIT
    printf 'box-prove %s\n' "$$" > "$tdir/in"
    sf() { sftp -F "$cfg" -b - box-backup-target 2>&1 <<< "$1"; }   # batch mode: a failing command gives a non-zero exit
    bad=0
    pass() { echo "box-prove: ok   $1"; }
    fail() { echo "box-prove: FAIL $1"; bad=1; }
    # 1 sign-in, and the folder it lands in
    if out=$(sf 'pwd') && grep -qx 'Remote working directory: /box' <<< "$out"; then pass "1 signs in over sftp; its folder is /box"; else fail "1 no sign-in, or its folder is not /box"; fi
    # 2 write, read back, remove
    if sf "put $tdir/in $name" >/dev/null && sf "get $name $tdir/back" >/dev/null && cmp -s "$tdir/in" "$tdir/back" && sf "rm $name" >/dev/null; then pass "2 writes a test file in /box, reads it back the same, removes it"; else fail "2 write, read-back or remove in /box"; sf "rm $name" >/dev/null || true; fi
    # 3 / is not writable, and no other folder in / opens
    if sf "put $tdir/in /$name" >/dev/null; then fail "3 / is writable (the test file was written)"; sf "rm /$name" >/dev/null || true; else pass "3 cannot write to /"; fi
    others=$(sf 'ls -1 /' | grep -v '^sftp>' | sed 's|^/||' | grep -v -x -e box -e '' || true)
    open=0
    for d in $others; do
      if sf "ls /$d" >/dev/null; then open=$((open + 1)); fi
    done
    [[ $open -eq 0 ]] && pass "3 cannot open any other folder in / (folders seen: $(wc -w <<< "$others"))" || fail "3 $open other folder(s) in / open"
    # 4 nothing outside the chroot
    if sf 'get /etc/passwd '"$tdir"'/pw' >/dev/null; then fail "4 /etc/passwd was read"; else pass "4 cannot read /etc/passwd"; fi
    # 5 no shell: a command over ssh must not run
    sh_out=$(timeout 30 ssh -n -F "$cfg" box-backup-target 'id -u' 2>&1 || true)
    if grep -Eq '^[0-9]+$' <<< "$sh_out"; then fail "5 a command over ssh ran (it printed a user id)"; else pass "5 a command over ssh runs no shell"; fi
    exit "$bad" ;;
  read-box-address)
    [[ -e $boxaddrfile ]] || exit 0
    [[ -r $boxaddrfile ]] || { echo "dev-worker-address: the box's address file is there but this user can't read it" >&2; exit 1; }
    out=$(check_shape < "$boxaddrfile") || { echo "dev-worker-address: the box's address file is not exactly one dev node address; refusing" >&2; exit 1; }
    printf '%s\n' "$out" ;;
  read-box-key)
    [[ -e $boxkeyfile ]] || exit 0
    [[ -r $boxkeyfile ]] || { echo "dev-worker-address: the box's backup key file is there but this user can't read it" >&2; exit 1; }
    out=$(check_pub < "$boxkeyfile") && [[ $out == "$(cat "$boxkeyfile")" ]] \
      || { echo "dev-worker-address: the box's backup key file is not exactly one ssh-ed25519 line (two fields, no comment); refusing" >&2; exit 1; }
    printf '%s\n' "$out" ;;
  box-key)
    [[ -d $handoff ]] || { echo "dev-worker-address: $handoff is missing (the agent_box role makes it)" >&2; exit 1; }
    kd=$keys/box-backup
    install -d -m 0700 "$kd"
    if [[ ! -e $kd/id_ed25519 || ! -e $kd/id_ed25519.pub ]]; then
      rm -f -- "$kd/id_ed25519.part" "$kd/id_ed25519.part.pub"
      ssh-keygen -q -t ed25519 -N '' -C "boxbackup@agent-box" -f "$kd/id_ed25519.part"
      chmod 600 "$kd/id_ed25519.part" "$kd/id_ed25519.part.pub"
      mv -f -- "$kd/id_ed25519.part.pub" "$kd/id_ed25519.pub"
      mv -f -- "$kd/id_ed25519.part" "$kd/id_ed25519"
    fi
    pub=$(check_pub < "$kd/id_ed25519.pub") || { echo "dev-worker-address: the box's public backup key is not one ssh-ed25519 line" >&2; exit 1; }
    printf '%s\n' "$pub" > "$boxkeyfile.part"
    chgrp "$group" "$boxkeyfile.part"
    chmod 0640 "$boxkeyfile.part"
    mv -f -- "$boxkeyfile.part" "$boxkeyfile"
    if [[ -r $hostkey_file ]] && hk=$(check_pub < "$hostkey_file" 2>/dev/null); then
      printf 'box-backup-target %s\n' "$hk" > "$kd/known_hosts.part"
      chmod 600 "$kd/known_hosts.part"
      mv -f -- "$kd/known_hosts.part" "$kd/known_hosts"
    fi
    mg=$(host_mgmt_address) || { rm -f -- "$boxaddrfile"; echo "dev-worker-address: the box's prod inventory copy does not name exactly one proxmox_host_mgmt_address; no address handed over" >&2; exit 1; }
    mg=$(printf '%s\n' "$mg" | check_ipv4) || { rm -f -- "$boxaddrfile"; echo "dev-worker-address: the host's mgmt address in the box's prod inventory copy is not one IPv4 address" >&2; exit 1; }
    ba=$(source_toward "$mg" | check_shape) \
      || { rm -f -- "$boxaddrfile"; echo "dev-worker-address: the box reaches the host's mgmt address from an address that is not a dev node address (a route outside the firewall?); no address handed over" >&2; exit 1; }
    cat > "$kd/ssh_config.part" <<CONF
# Written by dev-worker-address.sh box-key: how restic reaches the Proxmox host's backup store. No secret in it.
Host box-backup-target
  HostName $mg
  HostKeyAlias box-backup-target
  User boxbackup
  IdentityFile $kd/id_ed25519
  IdentitiesOnly yes
  BatchMode yes
  StrictHostKeyChecking yes
  UserKnownHostsFile $kd/known_hosts
  ForwardAgent no
  ConnectTimeout 20
  ServerAliveInterval 30
CONF
    chmod 600 "$kd/ssh_config.part"
    mv -f -- "$kd/ssh_config.part" "$kd/ssh_config"
    printf '%s\n' "$ba" > "$boxaddrfile.part"
    chgrp "$group" "$boxaddrfile.part"
    chmod 0640 "$boxaddrfile.part"
    mv -f -- "$boxaddrfile.part" "$boxaddrfile"
    echo "dev-worker-address: the box's backup key and address are in place (public half and address handed over, nothing else shown)" ;;
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
