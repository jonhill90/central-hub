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
  python3 -I -c "$(cat "$t/build.py")" "$t/src.yml" "$t/out.yml" /k/node.key /k/known_hosts /k "" /k/ca.crt "$1" "$t/settings.json" > "$t/err" 2>&1
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

exit $fail
