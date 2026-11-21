#!/usr/bin/env bash
# The firewall's Keycloak client names come from what the inventory already holds, with no new private value
# (hosts/ansible/roles/k8s_identity/defaults/main.yml k8s_identity_opnsense_hosts). Evaluated by ansible for real with test names only:
#   1. The client's names are the opnsense group's opnsense_cert_names when it has them.
#   2. With no opnsense group, or none of that key, they are opnsense.<zone> from k8s_identity_zone (itself a template on k8s_gateway_zone).
#   3. k8s_identity_opnsense_client false, or no zone, gives no name.
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
exit $fail
