#!/usr/bin/env bash
# The firewall sign-in's issuer comes from what the inventory already holds, with no new private value
# (roles/agent_box/tasks/proxmox_host_inventory.yml agent_box_host_opnsense_issuer). Evaluated by ansible for real with test names only:
#   1. The issuer is https://sso.<zone>/realms/lab from the first k8s_nodes host; an explicit issuer wins; with no zone it is empty.
# Usage: .github/hosts-check/tests/test_opnsense_sso_derive.sh   (needs ansible-core, PyYAML)
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
tasks = yaml.safe_load(open(roles + "/agent_box/tasks/proxmox_host_inventory.yml"))
fact = [x for x in tasks if x.get("name", "").endswith("Keycloak's issuer for the firewall's sign-in")][0]
play = [{"hosts": "k8s_nodes[0]", "gather_facts": False, "vars": {"agent_box_proxmox_host_opnsense_sso": {}},
         "tasks": [fact, {"debug": {"msg": "ISSUER={{ agent_box_host_opnsense_issuer }}"}}]}]
yaml.safe_dump(play, open(t + "/issuer.yml", "w"))
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
o=$(run issuer.yml "$node"); [ "$o" = 'ISSUER=https://sso.zone.example.test/realms/lab' ] && ok "1a. the issuer from the zone, sso and lab" || bad "1a. [$o]"
o=$(run issuer.yml "$node" -e '{"agent_box_proxmox_host_opnsense_sso": {"issuer": "https://id.example.test/realms/x"}}'); [ "$o" = 'ISSUER=https://id.example.test/realms/x' ] && ok "1b. an explicit issuer wins" || bad "1b. [$o]"
o=$(run issuer.yml 'all:
  children:
    k8s_nodes:
      hosts: {n1: {ansible_connection: local}}'); [ "$o" = 'ISSUER=' ] && ok "1c. no zone: empty issuer" || bad "1c. [$o]"
exit $fail
