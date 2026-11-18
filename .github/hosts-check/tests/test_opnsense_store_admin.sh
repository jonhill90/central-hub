#!/usr/bin/env bash
# The opnsense_lab role's store admin rule (tasks/store_admin.yml, D-0062 rule 4), offline (no firewall, no API):
#   1. With the real VLAN file and dev as the box's VLAN, the check passes at sequence 15: no other rule the role
#      numbers uses it, nor the app access or backup target rules in use, and it sits below dev's first rule (90).
#   2. The check fails for: a source or an address that is not one IPv4 address, a VLAN tag not in the file, and a
#      sequence another rule uses (5, a management pass; 1, an agent box target; 11, an app access rule; 13, a backup
#      target rule; 90, dev's own first rule) or not below the VLAN's first rule.
#   3. The app access and backup target checks refuse the store admin rule's sequence while it is set.
#   4. The rule task opens tcp 443 only, from the box's /32 to the admin address's /32, on the box's VLAN, and the
#      rule is removed while the input is unset.
# Usage: .github/hosts-check/tests/test_opnsense_store_admin.sh   (needs ansible-core)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
role=$root/hosts/ansible/roles/opnsense_lab
vlan_file=$root/hosts/ansible/inventories/home/group_vars/all/vlans.yml
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

cat > "$w/settings.yml" <<'YML'
opnsense_lab_vlan_settings:
  prod: { ifname: opt1, dhcp: true, bootstrap: false }
  qa: { ifname: opt2, dhcp: false, bootstrap: false }
  dev: { ifname: opt3, dhcp: true, bootstrap: false }
  mgmt: { ifname: lan, dhcp: false, bootstrap: true }
  tenant: { ifname: opt4, dhcp: true, bootstrap: false, mgmt_pass: false }
opnsense_lab_mgmt_tag: 50
opnsense_lab_agent_box:
  source: 192.0.2.10
  vlan: 30
  targets:
    - { name: Proxmox API, address: 192.0.2.50, port: 8006 }
    - { name: c1 API, address: 192.0.2.20, port: 6443 }
YML
good='{"opnsense_lab_app_access": {"vlan": 30, "gateway": "192.0.2.230", "sources": [{"name": "agent box", "address": "192.0.2.10"}]}, "opnsense_lab_backup_target": {"vlan": 10, "host": "192.0.2.50", "sources": [{"name": "prod node 200", "address": "192.0.2.20"}]}, "opnsense_lab_store_admin": {"vlan": 30, "source": "192.0.2.10", "address": "192.0.2.231"}}'

play() { # file, checks file
  cat > "$w/$1" <<YML
- hosts: localhost
  connection: local
  gather_facts: false
  vars_files: ["$vlan_file", "$w/settings.yml", "$role/defaults/main.yml", "$role/vars/main.yml"]
  tasks:
    - ansible.builtin.import_tasks: "$role/tasks/$2"
YML
}
play check.yml store_admin_checks.yml
play app.yml app_access_checks.yml
play backup.yml backup_target_checks.yml
cat >> "$w/check.yml" <<YML
    - ansible.builtin.copy:
        content: "{{ {'numbered': opnsense_lab_numbered_sequences, 'first': opnsense_lab_store_admin_first_vlan_rule | int, 'seq': opnsense_lab_store_admin_sequence} | to_json }}"
        dest: "$w/seq.json"
        mode: "0600"
YML
run() { ANSIBLE_LOCALHOST_WARNING=False ansible-playbook -i localhost, -e ansible_python_interpreter=auto_silent "$w/$1" -e "$2" >"$w/out" 2>&1; }

if run check.yml "$good"; then
  ok "the store admin rule at sequence 15 passes the check beside the app access and backup target rules"
  python3 -I - "$w/seq.json" <<'PY' && ok "the role's numbered sequences don't hold 15, and dev's first rule is 90" || bad "numbered sequences or dev's first rule are not as expected"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["seq"] == 15 and 15 not in d["numbered"], d
assert {1, 2, 5, 6, 7, 10, 90}.issubset(d["numbered"]), d
assert d["first"] == 90, d
PY
else bad "the good input fails the check"; cat "$w/out"; fi

refuse() { # description, play, message, extra vars JSON
  if run "$2" "$4"; then bad "$1 (the check passed)"; elif grep -q "$3" "$w/out"; then ok "$1"; else bad "$1 (failed some other way)"; cat "$w/out"; fi
}
sub() { python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); exec(sys.argv[2]); print(json.dumps(d))' "$good" "$1"; }
m="opnsense_lab_store_admin needs"
refuse "a source with a prefix is refused" check.yml "$m" "$(sub 'd["opnsense_lab_store_admin"]["source"]="192.0.2.10/32"')"
refuse "an address that is not an address is refused" check.yml "$m" "$(sub 'd["opnsense_lab_store_admin"]["address"]="openbao.example.com"')"
refuse "an address range is refused" check.yml "$m" "$(sub 'd["opnsense_lab_store_admin"]["address"]="192.0.2.224/27"')"
refuse "a VLAN tag not in the file is refused" check.yml "$m" "$(sub 'd["opnsense_lab_store_admin"]["vlan"]=99')"
refuse "a management pass sequence is refused" check.yml "$m" "$(sub 'd["opnsense_lab_store_admin_sequence"]=5')"
refuse "an agent box sequence is refused" check.yml "$m" "$(sub 'd["opnsense_lab_store_admin_sequence"]=1')"
refuse "an app access sequence in use is refused" check.yml "$m" "$(sub 'd["opnsense_lab_store_admin_sequence"]=11')"
refuse "a backup target sequence in use is refused" check.yml "$m" "$(sub 'd["opnsense_lab_store_admin_sequence"]=13')"
refuse "dev's own first rule's sequence is refused" check.yml "$m" "$(sub 'd["opnsense_lab_store_admin_sequence"]=90')"
refuse "a sequence not below the VLAN's first rule is refused" check.yml "$m" "$(sub 'd["opnsense_lab_store_admin_sequence"]=91')"
refuse "the app access check refuses the store admin sequence" app.yml "opnsense_lab_app_access needs" "$(sub 'd["opnsense_lab_store_admin_sequence"]=11')"
refuse "the backup target check refuses the store admin sequence" backup.yml "opnsense_lab_backup_target needs" "$(sub 'd["opnsense_lab_store_admin_sequence"]=13')"
if run app.yml "$good" && run backup.yml "$good"; then ok "the app access and backup target checks pass beside the store admin rule at 15"; else bad "the app access or backup target check fails beside the store admin rule"; cat "$w/out"; fi

# The rule as written: tcp 443 only, /32 at both ends, the box's VLAN, pass, quick; removed while unset.
python3 -I - "$role/tasks/store_admin.yml" <<'PY' && ok "the rule opens tcp 443 only, from the box's /32 to the admin address's /32, and is removed while unset" || bad "the rule task is not as narrow as it should be"
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1]))
t = next(t for t in tasks if t.get("name") == "Agent box to the store's admin address on 443")
r = t["oxlorg.opnsense.rule"]
assert r["action"] == "pass" and r["quick"] is True and r["direction"] == "in", r
assert r["protocol"] == "TCP" and r["destination_port"] == "443", r
assert r["source_net"] == "{{ opnsense_lab_store_admin.source }}/32", r
assert r["destination_net"] == "{{ opnsense_lab_store_admin.address }}/32", r
assert r["sequence"] == "{{ opnsense_lab_store_admin_sequence }}", r
assert "opnsense_lab_store_admin.vlan" in r["interface"][0], r
assert t["when"] == "opnsense_lab_store_admin is defined", t
g = next(t for t in tasks if t.get("name") == "No store admin rule when its input is unset")
gone = g["oxlorg.opnsense.rule"]
assert gone["state"] == "absent" and gone["description"] == r["description"], gone
assert g["when"] == "opnsense_lab_store_admin is not defined", g
PY

[[ $fail -eq 0 ]] && echo "opnsense store admin: all checks passed" || { echo "opnsense store admin: a check failed"; exit 1; }
