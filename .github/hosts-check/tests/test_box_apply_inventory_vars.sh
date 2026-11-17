#!/usr/bin/env bash
# The inventory file the role writes for box-apply (tasks/self_apply_inventory_vars.yml): the controller's host
# variables for the role, and nothing the play registered or set along the way. Run with ansible-playbook on
# localhost, with an inventory that holds role variables and a play that registers results the way the role does:
#   1. The inventory's role variables are in the result (agent_box_hostname, agent_box_allow, agent_box_secrets_store),
#      with the local connection and the interpreter added.
#   2. A registered result (agent_box_ca_stat, agent_box_key_files) and a set_fact name (agent_box_box_apply_from_start)
#      are not in the result, nor is a name the role does not declare.
#   3. agent_box_self_applying and agent_box_self_apply_commit are never in it.
#   4. The mutation (the old filter, every agent_box_ name) is caught by 2.
# Usage: .github/hosts-check/tests/test_box_apply_inventory_vars.sh   (needs ansible-playbook and python3)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

cat > "$t/inv.yml" <<'YML'
all:
  hosts:
    localhost:
      ansible_connection: local
      agent_box_hostname: boxname
      agent_box_allow: ["Bash(ls)"]
      agent_box_secrets_store: {vm: store}
      agent_box_self_apply_commit: "0000000000000000000000000000000000000000"
      agent_box_not_declared_by_the_role: x
YML
cat > "$t/play.yml" <<YML
- hosts: localhost
  gather_facts: false
  tasks:
    - ansible.builtin.stat: {path: /etc/hostname}
      register: agent_box_ca_stat
    - ansible.builtin.find: {paths: /etc, patterns: ["hostname"]}
      register: agent_box_key_files
    - ansible.builtin.set_fact: {agent_box_box_apply_from_start: true}
    - ansible.builtin.include_tasks: \$TASKS
    - ansible.builtin.copy:
        content: "{{ agent_box_box_apply_vars | to_json }}"
        dest: $t/vars.json
      check_mode: false
YML

run() {  # run <task file>: the inventory variables the file computes, as JSON in $t/vars.json
  sed "s|\$TASKS|$1|" "$t/play.yml" > "$t/play-run.yml"
  rm -f "$t/vars.json"
  ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
    ansible-playbook -i "$t/inv.yml" "$t/play-run.yml" --check -e "agent_box_role_dir=$root/hosts/ansible/roles/agent_box" 2>&1
}
has() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in d else 1)' "$t/vars.json" "$1"; }

TASKS=$root/hosts/ansible/roles/agent_box/tasks/self_apply_inventory_vars.yml
out=$(run "$TASKS") || { echo "$out"; bad "the play failed"; }
if [ -f "$t/vars.json" ]; then
  has agent_box_hostname && has agent_box_allow && has agent_box_secrets_store && has ansible_connection \
    && ok "the inventory's role variables are written, with the local connection" || bad "a role variable is missing: $(cat "$t/vars.json")"
  ! has agent_box_ca_stat && ! has agent_box_key_files && ! has agent_box_box_apply_from_start \
    && ok "registered results and a set_fact name are not written" || bad "a registered or set name is in the result: $(python3 -I -c 'import json,sys;print(sorted(json.load(open(sys.argv[1]))))' "$t/vars.json")"
  ! has agent_box_not_declared_by_the_role && ok "a name the role does not declare is not written" || bad "an undeclared name is in the result"
  ! has agent_box_self_apply_commit && ! has agent_box_self_applying && ok "the self-apply names are never written" || bad "a self-apply name is in the result"
fi

# Mutation: the old filter (every agent_box_ name) lets the registered results in.
sed "s#selectattr('key', 'in', agent_box_declared_names)#selectattr('key', 'match', '^agent_box_')#" "$TASKS" > "$t/mut.yml"
out=$(run "$t/mut.yml") || true
if [ -f "$t/vars.json" ] && has agent_box_ca_stat; then ok "mutation: the old filter writes the registered result"; else bad "mutation not caught: $out"; fi
exit $fail
