#!/usr/bin/env bash
# The opnsense_lab role's app access rules (tasks/app_access.yml), offline (no firewall, no API):
#   1. With the real VLAN file and dev as the sources' VLAN, the check passes for the agent box and the desktop VM at
#      sequences 11 and 12: no other rule the role numbers uses them, and both sit below dev's first rule (90).
#   2. The check fails for: an unknown source name, a repeated name, a source with a prefix, a Gateway that is not
#      an IPv4 address, a VLAN tag not in the file, more sources than sequences, a sequence another rule uses (5,
#      a management pass; 1, an agent box target), and a sequence not below the VLAN's first rule.
#   3. The rule task opens tcp 443 only, to the Gateway's /32, from each source's /32, on the sources' VLAN.
# Usage: .github/hosts-check/tests/test_opnsense_app_access.sh   (needs ansible-core)
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
good='{"opnsense_lab_app_access": {"vlan": 30, "gateway": "192.0.2.230", "sources": [{"name": "agent box", "address": "192.0.2.10"}, {"name": "desktop VM", "address": "192.0.2.91"}]}}'

cat > "$w/check.yml" <<YML
- hosts: localhost
  connection: local
  gather_facts: false
  vars_files: ["$vlan_file", "$w/settings.yml", "$role/defaults/main.yml", "$role/vars/main.yml"]
  tasks:
    - ansible.builtin.import_tasks: "$role/tasks/app_access_checks.yml"
    - ansible.builtin.copy:
        content: "{{ {'numbered': opnsense_lab_numbered_sequences, 'first': opnsense_lab_app_access_first_vlan_rule | int} | to_json }}"
        dest: "$w/seq.json"
        mode: "0600"
YML
check() { ANSIBLE_LOCALHOST_WARNING=False ansible-playbook -i localhost, -e ansible_python_interpreter=auto_silent "$w/check.yml" -e "$1" >"$w/out" 2>&1; }

if check "$good"; then
  ok "the agent box and the desktop VM at sequences 11 and 12 pass the check"
  python3 -I - "$w/seq.json" <<'PY' && ok "the role's numbered sequences hold neither 11 nor 12, and dev's first rule is 90" || bad "numbered sequences or dev's first rule are not as expected"
import json, sys
d = json.load(open(sys.argv[1]))
assert 11 not in d["numbered"] and 12 not in d["numbered"], d
assert {1, 2, 5, 6, 7, 10, 90, 100, 110, 120, 195, 200}.issubset(d["numbered"]), d
assert d["first"] == 90, d
PY
else bad "the good input fails the check"; cat "$w/out"; fi

refuse() { # description, extra vars JSON
  if check "$2"; then bad "$1 (the check passed)"; elif grep -q "opnsense_lab_app_access needs" "$w/out"; then ok "$1"; else bad "$1 (failed some other way)"; cat "$w/out"; fi
}
sub() { python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); exec(sys.argv[2]); print(json.dumps(d))' "$good" "$1"; }
refuse "an unknown source name is refused" "$(sub 'd["opnsense_lab_app_access"]["sources"][1]["name"]="laptop"')"
refuse "a repeated name is refused" "$(sub 'd["opnsense_lab_app_access"]["sources"][1]["name"]="agent box"')"
refuse "a source with a prefix is refused" "$(sub 'd["opnsense_lab_app_access"]["sources"][1]["address"]="192.0.2.0/24"')"
refuse "a Gateway that is not an address is refused" "$(sub 'd["opnsense_lab_app_access"]["gateway"]="grafana.example.com"')"
refuse "a VLAN tag not in the file is refused" "$(sub 'd["opnsense_lab_app_access"]["vlan"]=99')"
refuse "more sources than sequences are refused" "$(sub 'd["opnsense_lab_app_access_sequences"]=[11]')"
refuse "a management pass sequence is refused" "$(sub 'd["opnsense_lab_app_access_sequences"]=[5, 12]')"
refuse "an agent box sequence is refused" "$(sub 'd["opnsense_lab_app_access_sequences"]=[1, 12]')"
refuse "a sequence not below the VLAN's first rule is refused" "$(sub 'd["opnsense_lab_app_access_sequences"]=[11, 91]')"

# The rule as written: tcp 443 only, /32 at both ends, the sources' VLAN, pass, quick.
python3 -I - "$role/tasks/app_access.yml" <<'PY' && ok "the rule opens tcp 443 only, from each source's /32 to the Gateway's /32" || bad "the rule task is not as narrow as it should be"
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1]))
r = next(t for t in tasks if t.get("name") == "Named lab VMs to the c1 Gateway on 443")["oxlorg.opnsense.rule"]
assert r["action"] == "pass" and r["quick"] is True and r["direction"] == "in", r
assert r["protocol"] == "TCP" and r["destination_port"] == "443", r
assert r["source_net"] == "{{ item.address }}/32", r
assert r["destination_net"] == "{{ opnsense_lab_app_access.gateway }}/32", r
assert "opnsense_lab_app_access.vlan" in r["interface"][0], r
gone = next(t for t in tasks if t.get("name") == "No rules for app access sources that are gone")["oxlorg.opnsense.rule"]
assert gone["state"] == "absent" and gone["description"] == "Allow {{ item }} to c1 Gateway HTTPS", gone
PY

[[ $fail -eq 0 ]] && echo "opnsense app access: all checks passed" || { echo "opnsense app access: a check failed"; exit 1; }
