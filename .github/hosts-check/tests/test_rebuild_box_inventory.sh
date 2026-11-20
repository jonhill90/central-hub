#!/usr/bin/env bash
# The dev rebuild wrapper's copy of the dev inventory (hosts/ansible/roles/agent_box/files/rebuild.sh, the Python block
# that builds it), for the box's /32 to the hand-over:
#   1. With the in-cluster store on and box_cidr in the secrets store's settings, the copy sets
#      k8s_gitops_source_openbao_box_cidr to it; a box_cidr in the source inventory is dropped either way.
#   2. With no box_cidr in the settings, no settings file, or the in-cluster store off, the copy sets none.
#   3. A box_cidr that is not one IPv4 address as a /32 (a /24, loopback, a name, IPv6) stops the build.
#   4. The store's admin address (D-0062): admin_address in the settings, with the store on, sets
#      k8s_gitops_source_openbao_admin_address; one in the source inventory is dropped; one that is not IPv4, is loopback
#      or comes without box_cidr stops the build.
#   5. With the store on, box_cidr set and no admin_address in the settings, dev picks its own from the dev inventory's
#      k8s_control_plane_lb_cidr: the highest address below the pool's last that is not the Gateway's (k8s_gateway_address
#      or k8s_gitops_source_gateway_address, which may be a bare reference to the first), never printed. A Gateway value
#      that is neither an IPv4 address nor such a reference stops the build.
#      No pool in the inventory: none. A settings value wins. A pool that is not IPv4 or is under 4 addresses stops
#      the build. Without box_cidr: no address, and a line that names box_cidr.
# Usage: .github/hosts-check/tests/test_rebuild_box_inventory.sh   (needs python3 with PyYAML)
set -uo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)/hosts/ansible/roles/agent_box/files/rebuild.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

sed -n "/^python3 -I -c \"\$(cat <<'PY'$/,/^PY$/p" "$src" | sed '1d;$d' > "$t/build.py"
grep -q 'box_cidr' "$t/build.py" || { echo "FAIL: the inventory block was not found in rebuild.sh"; exit 1; }

cat > "$t/src.yml" <<'Y'
all:
  children:
    k8s_nodes:
      vars:
        k8s_gitops_source_openbao_box_cidr: 198.51.100.9/32
        k8s_gitops_source_openbao_admin_address: 198.51.100.40
      children:
        k8s_control_plane:
          hosts:
            node-cp: {ansible_host: 192.0.2.21}
        k8s_workers:
          hosts:
            node-w1: {ansible_host: 192.0.2.22}
Y
build() { # in_cluster settings-json-or-none
  rm -f "$t/out.yml"
  if [[ $2 == none ]]; then rm -f "$t/settings.json"; else echo "$2" > "$t/settings.json"; fi
  python3 -I -c "$(cat "$t/build.py")" "$t/src.yml" "$t/out.yml" /k/node.key /k/known_hosts /k "" /k/ca.crt "$1" "$t/settings.json" "${PROD_INV:-/nonexistent/inventory-hosts.yml}" "$t/ho" "$t/hk" "$t/ga" > "$t/err" 2>&1
  rc=$?
  cidr=$(python3 -I -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
found = []
def walk(n):
    if isinstance(n, dict):
        for k, v in n.items():
            if k == "k8s_gitops_source_openbao_box_cidr": found.append(v)
            else: walk(v)
    elif isinstance(n, list):
        for i in n: walk(i)
walk(d)
print(",".join(found) or "none")' "$t/out.yml" 2>/dev/null || echo missing)
  admin=$(python3 -I -c '
import sys, yaml
found = []
def walk(n):
    if isinstance(n, dict):
        for k, v in n.items():
            if k == "k8s_gitops_source_openbao_admin_address": found.append(v)
            else: walk(v)
walk(yaml.safe_load(open(sys.argv[1])))
print(",".join(found) or "none")' "$t/out.yml" 2>/dev/null || echo missing)
}

# 1
build true '{"address": "bao.invalid", "box_cidr": "192.0.2.30/32"}'
if [[ $rc -eq 0 && $cidr == 192.0.2.30/32 ]]; then ok "1. store on and box_cidr set: the copy carries the settings' /32 only"
else bad "1. rc=$rc cidr=$cidr $(cat "$t/err")"; fi

# 2
r2=""
build true '{"address": "bao.invalid"}'; r2+="$rc:$cidr "
build true none; r2+="$rc:$cidr "
build false '{"address": "bao.invalid", "box_cidr": "192.0.2.30/32"}'; r2+="$rc:$cidr "
if [[ $r2 == "0:none 0:none 0:none " ]]; then ok "2. no box_cidr, no settings file, or the store off: none set, the source's dropped"
else bad "2. $r2"; fi

# 3
r3=""
for c in 192.0.2.0/24 127.0.0.1/32 bao.invalid 2001:db8::1/128; do
  build true "{\"box_cidr\": \"$c\"}"; r3+="$rc:$cidr:$(grep -c 'must be one IPv4 address as a /32' "$t/err") "
done
if [[ $r3 == "1:missing:1 1:missing:1 1:missing:1 1:missing:1 " ]]; then ok "3. a /24, loopback, a name or IPv6 stops the build, with the reason"
else bad "3. $r3"; fi

# 4
r4=""
build true '{"box_cidr": "192.0.2.30/32", "admin_address": "192.0.2.40"}'; r4+="$rc:$admin "
build true '{"box_cidr": "192.0.2.30/32"}'; r4+="$rc:$admin "
build false '{"box_cidr": "192.0.2.30/32", "admin_address": "192.0.2.40"}'; r4+="$rc:$admin "
for a in 192.0.2.0/24 127.0.0.1 bao.invalid 2001:db8::1; do
  build true "{\"box_cidr\": \"192.0.2.30/32\", \"admin_address\": \"$a\"}"; r4+="$rc:$admin:$(grep -c 'admin_address' "$t/err") "
done
build true '{"admin_address": "192.0.2.40"}'; r4+="$rc:$admin:$(grep -c 'with box_cidr set' "$t/err")"
if [[ $r4 == "0:192.0.2.40 0:none 0:none 1:missing:1 1:missing:1 1:missing:1 1:missing:1 1:missing:1" ]]; then
  ok "4. admin_address with the store on: set, the source's dropped; a range, loopback, a name, IPv6 or no box_cidr stops the build"
else bad "4. $r4"; fi

# 5
pool() { # pool source-gateway [gateway]: the source inventory with dev's pool and its two Gateway address values
  python3 -I -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
v = d["all"]["children"]["k8s_nodes"]["vars"]
if sys.argv[2]: v["k8s_control_plane_lb_cidr"] = sys.argv[2]
if sys.argv[3]: v["k8s_gitops_source_gateway_address"] = sys.argv[3]
if sys.argv[4]: d["all"].setdefault("vars", {})["k8s_gateway_address"] = sys.argv[4]
yaml.safe_dump(d, open(sys.argv[1], "w"))' "$t/src.yml" "$1" "$2" "${3:-}"
}
cp "$t/src.yml" "$t/src.keep"
r5=""
pool 192.0.2.224/27 192.0.2.230; build true '{"box_cidr": "192.0.2.30/32"}'; r5+="$rc:$admin:$(grep -c "dev's own pick" "$t/err"):$(grep -c '192.0.2.254' "$t/err") "
cp "$t/src.keep" "$t/src.yml"; pool 192.0.2.224/27 192.0.2.254; build true '{"box_cidr": "192.0.2.30/32"}'; r5+="$rc:$admin "
build true '{"box_cidr": "192.0.2.30/32", "admin_address": "192.0.2.240"}'; r5+="$rc:$admin "
build false '{"box_cidr": "192.0.2.30/32"}'; r5+="$rc:$admin "
build true '{"address": "bao.invalid"}'; r5+="$rc:$admin:$(grep -c 'box_cidr is not in the secrets store' "$t/err") "
cp "$t/src.keep" "$t/src.yml"; build true '{"box_cidr": "192.0.2.30/32"}'; r5+="$rc:$admin "
for p in 192.0.2.224/31 2001:db8::/120 192.0.2.225/27; do
  cp "$t/src.keep" "$t/src.yml"; pool "$p" ""; build true '{"box_cidr": "192.0.2.30/32"}'; r5+="$rc:$admin:$(grep -c 'k8s_control_plane_lb_cidr' "$t/err") "
done
# The Gateway given as a reference to k8s_gateway_address (hosts.example.yml), or only as k8s_gateway_address.
cp "$t/src.keep" "$t/src.yml"; pool 192.0.2.224/27 '{{ k8s_gateway_address }}' 192.0.2.254; build true '{"box_cidr": "192.0.2.30/32"}'; r5+="$rc:$admin "
cp "$t/src.keep" "$t/src.yml"; pool 192.0.2.224/27 "" 192.0.2.254; build true '{"box_cidr": "192.0.2.30/32"}'; r5+="$rc:$admin "
# A Gateway value that is neither an address nor a bare reference to one stops the build.
for g in '{{ k8s_gateway_address | default("x") }}' gw.invalid 2001:db8::1; do
  cp "$t/src.keep" "$t/src.yml"; pool 192.0.2.224/27 "$g" 192.0.2.254; build true '{"box_cidr": "192.0.2.30/32"}'; r5+="$rc:$admin:$(grep -c 'must be one IPv4 address (or a reference to one)' "$t/err") "
done
cp "$t/src.keep" "$t/src.yml"
if [[ $r5 == "0:192.0.2.254:1:0 0:192.0.2.253 0:192.0.2.240 0:none 0:none:1 0:none 1:missing:1 1:missing:1 1:missing:1 0:192.0.2.253 0:192.0.2.253 1:missing:1 1:missing:1 1:missing:1 " ]]; then
  ok "5. no admin_address: dev's own pick below the pool's last, never the Gateway's, never printed; none without a pool, the store or box_cidr (named); a settings value wins; a bad pool stops the build"
else bad "5. $r5 $(cat "$t/err")"; fi

# 6. Dev's restore from the Proxmox host's copy: the seed folder is always set, and the seed address is the host's address read from the
#    proxmox group of this inventory, or else of the prod inventory copy, never printed; one that is not an address stops the build.
seedvars() { python3 -I -c 'import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
def find(n):
    if isinstance(n, dict):
        if "k8s_nodes" in n and isinstance(n["k8s_nodes"], dict): return n["k8s_nodes"].get("vars", {})
        for x in n.values():
            r = find(x)
            if r is not None: return r
v = find(d)
print(v.get("k8s_backup_sftp_seed_dir", "-"), v.get("k8s_backup_sftp_seed_address", "-"))' "$t/out.yml"; }
flags() { python3 -I -c 'import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
def find(n):
    if isinstance(n, dict):
        if "k8s_nodes" in n and isinstance(n["k8s_nodes"], dict): return n["k8s_nodes"].get("vars", {})
        for x in n.values():
            r = find(x)
            if r is not None: return r
v = find(d)
print(v.get("k8s_backup_sftp", "-"), v.get("k8s_backup_azure_identity", "-"))' "$t/out.yml"; }
cp "$t/src.keep" "$t/src.yml"; build false none; r6a=$(seedvars)
printf 'all:\n  children:\n    proxmox:\n      hosts:\n        pve: {proxmox_host_mgmt_address: 192.0.2.50}\n' > "$t/prod.yml"
PROD_INV=$t/prod.yml build false none; r6b=$(seedvars)
printf 'all:\n  children:\n    proxmox:\n      hosts:\n        pve: {proxmox_host_mgmt_address: pve.example.com}\n' > "$t/prod.yml"
PROD_INV=$t/prod.yml build false none; rc6=$rc; err6=$(cat "$t/err")
if [[ $r6a == "/k/dev/backup-sftp -" && $r6b == "/k/dev/backup-sftp 192.0.2.50" && $rc6 == 1 && $err6 == *"proxmox_host_mgmt_address is not an IP address"* && $err6 != *pve.example.com* ]]; then
  ok "6. the seed folder is set; the host's address comes from the prod copy, none without one, a bad one stops the build and is not printed"
else bad "6. [$r6a] [$r6b] rc=$rc6 $err6"; fi

# 7. Step 3: dev's restore moves to the Proxmox host's copy only when everything is in place: the host's address, the worker's key pair and the
#    pinned host key, AND the two jobs' markers (the restore-reader apply put this key on the host for this address; the firewall apply opened
#    this address), each a sha256 that must match the handoff files as they are now. Then sftp on and the Azure reader off in the box's built
#    copy. Anything missing or stale leaves the inventory's own values.
mkdir -p "$t/kd/dev/backup-sftp" "$t/ho" "$t/hk" "$t/ga"
buildk() { rm -f "$t/out.yml"; python3 -I -c "$(cat "$t/build.py")" "$t/src.yml" "$t/out.yml" /k/node.key /k/known_hosts "$t/kd" "" /k/ca.crt false "$t/none.json" "$t/prod.yml" "$t/ho" "$t/hk" "$t/ga" > "$t/err" 2>&1; rc=$?; }
sha() { python3 -I -c 'import hashlib,sys; print(hashlib.sha256("".join(l + "\n" for l in sys.argv[1:]).encode()).hexdigest())' "$@"; }
printf 'all:\n  children:\n    proxmox:\n      hosts:\n        pve: {proxmox_host_mgmt_address: 192.0.2.50}\n' > "$t/prod.yml"
cp "$t/src.keep" "$t/src.yml"
key7='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample'; addr7=10.1.30.12
buildk; f7a=$(flags)
for e in key pub; do echo x > "$t/kd/dev/backup-sftp/node-w1.$e"; done; buildk; f7b=$(flags)
echo "c1-backup-target ssh-ed25519 AAAA" > "$t/kd/dev/backup-sftp/node-w1.known_hosts"; buildk; f7c=$(flags)   # files, no markers
echo "$addr7" > "$t/ho/dev-worker-address"; echo "$key7" > "$t/ho/dev-worker-backup.pub"
sha "$key7" "$addr7" > "$t/hk/reader-applied"; buildk; f7d=$(flags)                                              # the key is on the host, no rule
sha "$addr7" > "$t/ga/dev-rule-applied"; buildk; f7e=$(flags)                                                     # both: switch
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIother" > "$t/ho/dev-worker-backup.pub"; buildk; f7f=$(flags)           # key changed since: stale
echo "$key7" > "$t/ho/dev-worker-backup.pub"; echo 10.1.30.13 > "$t/ho/dev-worker-address"; buildk; f7g=$(flags) # address changed since: stale
echo "$addr7" > "$t/ho/dev-worker-address"; rm -f "$t/hk/reader-applied"; buildk; f7h=$(flags)                    # the host marker is gone
sha "$key7" "$addr7" > "$t/hk/reader-applied"
printf 'all:\n  children:\n    proxmox:\n      hosts:\n        pve: {}\n' > "$t/prod.yml"; buildk; f7i=$(flags)  # no host address
if [[ $f7a == "- -" && $f7b == "- -" && $f7c == "- -" && $f7d == "- -" && $f7e == "True False" && $f7f == "- -" && $f7g == "- -" && $f7h == "- -" && $f7i == "- -" ]]; then
  ok "7. sftp on and the Azure reader off only with the files, the host's address and both jobs' markers matching the handoff; a missing or stale one leaves the inventory alone"
else bad "7. [$f7a] [$f7b] [$f7c] [$f7d] [$f7e] [$f7f] [$f7g] [$f7h] [$f7i] $(cat "$t/err")"; fi

exit $fail
