#!/usr/bin/env bash
# The firewall's Keycloak client names come from what the inventory already holds, with no new private value
# (hosts/ansible/roles/k8s_identity/defaults/main.yml k8s_identity_opnsense_hosts). Evaluated by ansible for real with test names only:
#   1. The client's names are the opnsense group's opnsense_cert_names when it has them.
#   2. With no opnsense group, or none of that key, they are opnsense.<zone> from k8s_identity_zone (itself a template on k8s_gateway_zone).
#   3. k8s_identity_opnsense_client false, or no zone, gives no name.
#   4. A run with tags always (the box's `identity-values`) adds OPNSENSE_CLIENT_SECRET to a values file as 64 random hex digits, prints only
#      the key's name, keeps the other lines, and a second run adds nothing.
# Usage: .github/hosts-check/tests/test_opnsense_client_derive.sh   (needs ansible-core, PyYAML)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
root=$PWD
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
roles=$root/hosts/ansible/roles
python3 -I - "$roles" "$t" <<'PY'
import sys, yaml
roles, t = sys.argv[1:3]
play = [{"hosts": "k8s_nodes[0]", "gather_facts": False, "vars_files": [roles + "/k8s_identity/defaults/main.yml"],
         "tasks": [{"debug": {"msg": "HOSTS={{ k8s_identity_opnsense_hosts | to_json }}"}}]}]
yaml.safe_dump(play, open(t + "/hosts.yml", "w"))
PY
run() { # playbook, inventory text, extra args
  printf '%s\n' "$2" > "$t/inv.yml"
  ( cd "$t" && ANSIBLE_NOCOLOR=1 ansible-playbook -i inv.yml "$1" "${@:3}" 2>&1 ) | sed -n 's/.*"msg": "\(.*\)"$/\1/p' | sed 's/\\"/"/g'
}
node='all:
  children:
    k8s_nodes:
      hosts: {n1: {ansible_connection: local}}
      vars: {k8s_gateway_zone: zone.example.test, k8s_identity_zone: "{{ k8s_gateway_zone }}"}'
fw='    opnsense:
      hosts: {fw: {ansible_connection: local, opnsense_cert_names: ["gui.zone.example.test"]}}'
nofw='    opnsense:
      hosts: {fw: {ansible_connection: local}}'
o=$(run hosts.yml "$node
$fw"); [ "$o" = 'HOSTS=["gui.zone.example.test"]' ] && ok "1. the GUI names are the firewall's opnsense_cert_names" || bad "1. [$o]"
o=$(run hosts.yml "$node"); [ "$o" = 'HOSTS=["opnsense.zone.example.test"]' ] && ok "2a. no opnsense group: opnsense.<zone>, the zone through its template" || bad "2a. [$o]"
o=$(run hosts.yml "$node
$nofw"); [ "$o" = 'HOSTS=["opnsense.zone.example.test"]' ] && ok "2b. an opnsense host with no cert names: opnsense.<zone>" || bad "2b. [$o]"
o=$(run hosts.yml "$node" -e k8s_identity_opnsense_client=false); [ "$o" = 'HOSTS=[]' ] && ok "3a. k8s_identity_opnsense_client false: no name" || bad "3a. [$o]"
o=$(run hosts.yml 'all:
  children:
    k8s_nodes:
      hosts: {n1: {ansible_connection: local}}
      vars: {k8s_identity_zone: ""}'); [ "$o" = 'HOSTS=[]' ] && ok "3b. no zone: no name" || bad "3b. [$o]"
# 4
cat > "$t/vinv.yml" <<'INV'
all:
  children:
    k8s_control_plane:
      hosts: {cp1: {ansible_connection: local}}
      vars: {k8s_identity_zone: zone.example.test, k8s_identity_owner_username: owner}
    k8s_workers:
      hosts: {w1: {ansible_connection: local}}
INV
printf 'GRAFANA_CLIENT_SECRET=keep-me\n' > "$t/identity.env"
vrun() { ( cd "$root/hosts/ansible" && ANSIBLE_ROLES_PATH=roles ANSIBLE_NOCOLOR=1 ansible-playbook -i "$t/vinv.yml" playbooks/k8s-identity.yml --tags always \
  -e ansible_become=false -e "k8s_identity_values_file=$t/identity.env" 2>&1 ); }
out1=$(vrun); rc1=$?; sum1=$(sha256sum "$t/identity.env" | cut -d' ' -f1); out2=$(vrun); sum2=$(sha256sum "$t/identity.env" | cut -d' ' -f1)
val=$(sed -n 's/^OPNSENSE_CLIENT_SECRET=//p' "$t/identity.env")
if [ $rc1 = 0 ] && [[ $val =~ ^[0-9a-f]{64}$ ]] && grep -q '^GRAFANA_CLIENT_SECRET=keep-me$' "$t/identity.env" && [ "$sum1" = "$sum2" ] && [[ $out2 == *"changed=0"* ]] &&
   [[ $out1 != *"$val"* ]]; then
  ok "4. tags always adds a random OPNSENSE_CLIENT_SECRET, keeps the other lines, prints no value, and a second run changes nothing"
else bad "4. rc=$rc1 value-shape=$([[ $val =~ ^[0-9a-f]{64}$ ]] && echo ok || echo no)"; fi
exit $fail
