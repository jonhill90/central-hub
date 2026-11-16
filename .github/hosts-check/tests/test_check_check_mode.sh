#!/usr/bin/env bash
# check-check-mode.py (a pipeline job's check run changes nothing; Library plans/r1-host-job/DESIGN.md v3.1):
#   1. The repository's own proxy playbook passes.
#   2. Read-only modules and a fixed `command` with changed_when: false pass, in a block too.
#   3. `command` with check_mode false and no changed_when: false fails.
#   4. A templated value in the command line that is not `| quote` fails; a quoted one passes.
#   5. A module that writes (copy) with check_mode false fails, also inside a role the play includes.
# Usage: .github/hosts-check/tests/test_check_check_mode.sh   (needs python3 with PyYAML)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
lint=$root/.github/hosts-check/check-check-mode.py
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

python3 "$lint" "$root" playbooks/proxmox-proxy.yml > "$t/1.out" 2>&1 && ok "1 the proxy playbook passes" || bad "1 $(cat "$t/1.out")"

mk() { # mk <tasks yaml>: a tree with role r, run by playbooks/p.yml, and role inner, included by r
  rm -rf "$t/tree"; mkdir -p "$t/tree/hosts/ansible/playbooks" "$t/tree/hosts/ansible/roles/r/tasks" "$t/tree/hosts/ansible/roles/inner/tasks"
  printf -- '- hosts: h\n  roles: [r]\n' > "$t/tree/hosts/ansible/playbooks/p.yml"
  printf '%s\n' "$1" > "$t/tree/hosts/ansible/roles/r/tasks/main.yml"
  printf '%s\n' "${2:-[]}" > "$t/tree/hosts/ansible/roles/inner/tasks/main.yml"
}
run() { python3 "$lint" "$t/tree" playbooks/p.yml > "$t/out" 2>&1; }

mk '- name: a
  ansible.builtin.slurp: {src: /x}
  check_mode: false
- block:
    - name: b
      ansible.builtin.command: apache2ctl configtest
      changed_when: false
      check_mode: false'
run && ok "2 read-only modules and a fixed command pass" || bad "2 $(cat "$t/out")"

mk '- name: c
  ansible.builtin.command: systemctl restart x
  check_mode: false'
run && bad "3 a command with no changed_when false passed" || ok "3 a command with no changed_when false fails"

mk '- name: d
  ansible.builtin.shell:
    cmd: rm -rf {{ path }}
  changed_when: false
  check_mode: false'
run && bad "4 an unquoted value passed" || ok "4 an unquoted value fails"
mk '- name: e
  ansible.builtin.shell:
    cmd: cat {{ path | quote }}
  changed_when: false
  check_mode: false'
run && ok "4 a quoted value passes" || bad "4 quoted: $(cat "$t/out")"

mk '- name: f
  ansible.builtin.include_role: {name: inner}' '- name: g
  ansible.builtin.copy: {dest: /x, content: y}
  check_mode: false'
run && bad "5 a copy in an included role passed" || { grep -q 'inner/tasks/main.yml: g: module copy' "$t/out" && ok "5 a write in an included role fails" || bad "5 $(cat "$t/out")"; }

exit "$fail"
