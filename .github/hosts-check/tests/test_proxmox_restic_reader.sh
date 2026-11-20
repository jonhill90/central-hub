#!/usr/bin/env bash
# The restore-reader playbook (hosts/ansible/playbooks/proxmox-restic-reader.yml), run for real against a stand-in proxmox_restic_sftp role
# that records the two inputs the real role takes:
#   1. With the handoff address (proxmox_restic_reader_from), every key's `from` is that address, it reaches the role's reader keys and
#      its no_root_from, and it wins over a different `from` in the inventory's list.
#   2. Without it (a run from the controller) each key keeps its own `from`.
#   3. A key that is not ssh-ed25519, a `from` that is not one IPv4, an empty list, or no `from` anywhere stops the play before the role.
#   4. The playbook never sets the writer's keys.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
mkdir -p "$t/roles/proxmox_restic_sftp/tasks"
cat > "$t/roles/proxmox_restic_sftp/tasks/main.yml" <<'YML'
- ansible.builtin.copy:
    content: "{{ {'keys': proxmox_restic_sftp_reader_keys, 'no_root': proxmox_restic_sftp_no_root_from, 'reader': proxmox_restic_sftp_set_reader, 'writer': proxmox_restic_sftp_set_writer | default(false)} | to_json }}"
    dest: "{{ role_out }}"
    mode: "0600"
YML
key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample dev-worker'
run() { # extra vars JSON
  rm -f "$t/role.json"
  ANSIBLE_ROLES_PATH=$t/roles ANSIBLE_LOCALHOST_WARNING=False ansible-playbook -i "$t/inv.yml" -e "role_out=$t/role.json" -e "$1" \
    "$src/hosts/ansible/playbooks/proxmox-restic-reader.yml" > "$t/out" 2>&1
}
printf 'proxmox:\n  hosts:\n    h: {ansible_connection: local, ansible_python_interpreter: auto_silent}\n' > "$t/inv.yml"
rd() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(d[sys.argv[2]]))' "$t/role.json" "$1"; }

if run "{\"proxmox_restic_reader_keys\":[{\"key\":\"$key\",\"from\":\"192.0.2.99\"}],\"proxmox_restic_reader_from\":\"10.1.30.12\"}" \
   && [[ $(rd keys) == "[{\"key\": \"$key\", \"from\": \"10.1.30.12\"}]" && $(rd no_root) == '["10.1.30.12"]' && $(rd reader) == true ]]; then
  ok "1 the handoff address is the key's from and the no_root_from, and wins over the inventory's from"
else bad "1 $(cat "$t/out" | tail -5) keys=$(rd keys 2>&1)"; fi
if run "{\"proxmox_restic_reader_keys\":[{\"key\":\"$key\"}],\"proxmox_restic_reader_from\":\"10.1.30.12\"}" && [[ $(rd no_root) == '["10.1.30.12"]' ]]; then
  ok "1 a key with no from of its own takes the handoff address"; else bad "1 no from of its own"; fi
if run "{\"proxmox_restic_reader_keys\":[{\"key\":\"$key\",\"from\":\"192.0.2.99\"}]}" && [[ $(rd keys) == "[{\"key\": \"$key\", \"from\": \"192.0.2.99\"}]" && $(rd no_root) == '["192.0.2.99"]' ]]; then
  ok "2 with no handoff the key keeps its own from"; else bad "2 $(tail -5 "$t/out")"; fi

refuse() { if run "$2"; then bad "3 $1: the play ran the role"; elif [[ ! -e $t/role.json ]]; then ok "3 $1: stopped before the role"; else bad "3 $1: role ran"; fi; }
refuse "an rsa key" '{"proxmox_restic_reader_keys":[{"key":"ssh-rsa AAAAB3","from":"192.0.2.9"}]}'
refuse "a from that is not an address" "{\"proxmox_restic_reader_keys\":[{\"key\":\"$key\",\"from\":\"host.example\"}]}"
refuse "an empty list" '{"proxmox_restic_reader_keys":[]}'
refuse "no from anywhere" "{\"proxmox_restic_reader_keys\":[{\"key\":\"$key\"}]}"
refuse "a handoff address that is not an address" "{\"proxmox_restic_reader_keys\":[{\"key\":\"$key\"}],\"proxmox_restic_reader_from\":\"10.1.30.5/32\"}"
! grep -Eq 'set_writer|writer_keys' "$src/hosts/ansible/playbooks/proxmox-restic-reader.yml" && ok "4 the playbook never sets the writer's keys" || bad "4 it mentions the writer's keys"
key2='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIother dev-worker-2'
if run "{\"proxmox_restic_reader_keys\":[{\"key\":\"$key\",\"from\":\"192.0.2.99\"}],\"proxmox_restic_reader_key\":\"$key2\",\"proxmox_restic_reader_from\":\"10.1.30.12\"}" \
   && [[ $(rd keys) == "[{\"key\": \"$key2\", \"from\": \"10.1.30.12\"}]" && $(rd no_root) == '["10.1.30.12"]' ]]; then
  ok "5 the handoff key (proxmox_restic_reader_key) is the one key, over the inventory's list, with the handoff address"
else bad "5 $(tail -5 "$t/out") keys=$(rd keys 2>&1)"; fi
refuse "a handoff key that is not ed25519" '{"proxmox_restic_reader_key":"ssh-rsa AAAAB3","proxmox_restic_reader_from":"10.1.30.12"}'
exit "$fail"
