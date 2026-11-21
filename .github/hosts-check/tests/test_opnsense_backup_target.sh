#!/usr/bin/env bash
# The opnsense_lab role's backup target rules (tasks/backup_target.yml), offline (no firewall, no API):
#   1. With the real VLAN file and prod as the sources' VLAN, the check passes for the two prod nodes at sequences
#      13 and 14: no other rule the role numbers uses them, nor the app access rules.
#   2. The check fails for: an unknown source name, a repeated name, a source with a prefix, a host that is not an
#      IPv4 address, a VLAN tag not in the file, more sources than sequences, a sequence another rule uses (10,
#      prod's own first rule; 5, a management pass; 1, an agent box target; 11, an app access rule).
#   4. A source may name its own VLAN (dev's worker on 30 at sequence 17, as well as the two prod nodes on 10); the check
#      refuses a source VLAN tag that is not in the file, and the rule's interface follows the source's VLAN.
#   3. The rule task opens tcp 22 only, to the host's /32, from each node's /32, on the sources' VLAN.
# Usage: .github/hosts-check/tests/test_opnsense_backup_target.sh   (needs ansible-core)
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
good='{"opnsense_lab_app_access": {"vlan": 30, "gateway": "192.0.2.230", "sources": [{"name": "agent box", "address": "192.0.2.10"}]}, "opnsense_lab_backup_target": {"vlan": 10, "host": "192.0.2.50", "sources": [{"name": "prod node 200", "address": "192.0.2.20"}, {"name": "prod node 201", "address": "192.0.2.21"}]}}'

cat > "$w/check.yml" <<YML
- hosts: localhost
  connection: local
  gather_facts: false
  vars_files: ["$vlan_file", "$w/settings.yml", "$role/defaults/main.yml", "$role/vars/main.yml", "$w/case.json"]
  tasks:
    - ansible.builtin.import_tasks: "$role/tasks/backup_target_checks.yml"
    - ansible.builtin.copy:
        content: "{{ {'numbered': opnsense_lab_numbered_sequences, 'sources': (opnsense_lab_backup_target.sources | default([]))} | to_json }}"
        dest: "$w/seq.json"
        mode: "0600"
YML
# The case goes in as a vars file, not as extra vars, which no set_fact can override (the check joins the box's extra sources with set_fact, as inventory vars are).
check() { printf '%s' "$1" > "$w/case.json"; ANSIBLE_LOCALHOST_WARNING=False ansible-playbook -i localhost, -e ansible_python_interpreter=auto_silent "$w/check.yml" >"$w/out" 2>&1; }

if check "$good"; then
  ok "the two prod nodes at sequences 13 and 14 pass the check"
  python3 -I - "$w/seq.json" <<'PY' && ok "the role's numbered sequences hold none of 13, 14 and 17, and prod's own rules are 10 to 40" || bad "numbered sequences are not as expected"
import json, sys
d = json.load(open(sys.argv[1]))
assert not {13, 14, 17, 18} & set(d["numbered"]), d
assert {1, 2, 5, 6, 7, 10, 20, 30, 40}.issubset(d["numbered"]), d
PY
else bad "the good input fails the check"; cat "$w/out"; fi

refuse() { # description, extra vars JSON
  if check "$2"; then bad "$1 (the check passed)"; elif grep -q "opnsense_lab_backup_target needs" "$w/out"; then ok "$1"; else bad "$1 (failed some other way)"; cat "$w/out"; fi
}
sub() { python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); exec(sys.argv[2]); print(json.dumps(d))' "$good" "$1"; }
refuse "an unknown source name is refused" "$(sub 'd["opnsense_lab_backup_target"]["sources"][1]["name"]="laptop"')"
refuse "a repeated name is refused" "$(sub 'd["opnsense_lab_backup_target"]["sources"][1]["name"]="prod node 200"')"
refuse "a source with a prefix is refused" "$(sub 'd["opnsense_lab_backup_target"]["sources"][1]["address"]="192.0.2.0/24"')"
refuse "a host that is not an address is refused" "$(sub 'd["opnsense_lab_backup_target"]["host"]="pve.example.com"')"
refuse "a VLAN tag not in the file is refused" "$(sub 'd["opnsense_lab_backup_target"]["vlan"]=99')"
refuse "more sources than sequences are refused" "$(sub 'd["opnsense_lab_backup_target_sequences"]=[13]')"
refuse "prod's own first rule's sequence is refused" "$(sub 'd["opnsense_lab_backup_target_sequences"]=[10, 14]')"
refuse "a management pass sequence is refused" "$(sub 'd["opnsense_lab_backup_target_sequences"]=[5, 14]')"
refuse "an agent box sequence is refused" "$(sub 'd["opnsense_lab_backup_target_sequences"]=[1, 14]')"
refuse "an app access sequence in use is refused" "$(sub 'd["opnsense_lab_backup_target_sequences"]=[11, 14]')"

# A dev worker on its own VLAN passes; a source VLAN not in the file is refused.
withdev=$(sub 'd["opnsense_lab_backup_target"]["sources"].append({"name": "dev worker", "address": "192.0.2.30", "vlan": 30})')
if check "$withdev"; then ok "a dev worker on VLAN 30 as a third source at sequence 17 passes"; else bad "a dev worker on VLAN 30 is refused"; cat "$w/out"; fi
# The store admin rule (default sequence 15) and the Proxmox web rule (16) are set at the same time: the dev worker's default 17 is clear of both,
# and the old 15 would collide.
withstore=$(sub 'd["opnsense_lab_backup_target"]["sources"].append({"name": "dev worker", "address": "192.0.2.30", "vlan": 30}); d["opnsense_lab_store_admin"]={"vlan": 30}; d["opnsense_lab_proxmox_web"]={"vlan": 30}')
if check "$withstore"; then ok "with the store admin and Proxmox web rules set, the third source at sequence 17 passes"; else bad "the third source is refused with the store admin rule set"; cat "$w/out"; fi
refuse "sequence 15 collides with the store admin rule when it is set" "$(echo "$withstore" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); d["opnsense_lab_backup_target_sequences"]=[13, 14, 15]; print(json.dumps(d))')"
# The box's own extra source (the firewall job's vars file: the dev worker's handoff address) joins the inventory's two and is checked like them.
extra=$(sub 'd["opnsense_lab_backup_target_extra_sources"]=[{"name": "dev worker", "address": "192.0.2.30", "vlan": 30}]')
if check "$extra"; then ok "an extra source named dev worker on VLAN 30 joins the two prod nodes and passes"; else bad "the extra source is refused"; cat "$w/out"; fi
# The box's address joins as a fourth source, named agent box, at sequence 18; alone it is the third, at 17; both are clear of the store admin (15) and the Proxmox web (16) rules.
both=$(sub 'd["opnsense_lab_backup_target_extra_sources"]=[{"name": "dev worker", "address": "192.0.2.30", "vlan": 30}, {"name": "agent box", "address": "192.0.2.10", "vlan": 30}]; d["opnsense_lab_store_admin"]={"vlan": 30}; d["opnsense_lab_proxmox_web"]={"vlan": 30}')
if check "$both"; then ok "the dev worker and the agent box as extra sources (four sources, sequences 13 14 17 18) pass with the store admin and Proxmox web rules set"; else bad "dev worker and agent box are refused"; cat "$w/out"; fi
boxonly=$(sub 'd["opnsense_lab_backup_target_extra_sources"]=[{"name": "agent box", "address": "192.0.2.10", "vlan": 30}]')
if check "$boxonly"; then ok "the agent box alone as an extra source passes"; else bad "the agent box alone is refused"; cat "$w/out"; fi
refuse "a fourth source with the sequences cut to three is refused" "$(echo "$both" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); d["opnsense_lab_backup_target_sequences"]=[13, 14, 17]; print(json.dumps(d))')"
# A dev worker already in the inventory's list is replaced by the box's extra source of the same name (the box's address wins), so the
# unique-name check can't stop the firewall job.
dup=$(sub 'd["opnsense_lab_backup_target"]["sources"].append({"name": "dev worker", "address": "192.0.2.77", "vlan": 30}); d["opnsense_lab_backup_target_extra_sources"]=[{"name": "dev worker", "address": "192.0.2.30", "vlan": 30}]')
if check "$dup" && python3 -I -c 'import json,sys; s=json.load(open(sys.argv[1]))["sources"]; assert [x["address"] for x in s if x["name"]=="dev worker"]==["192.0.2.30"] and len(s)==3, s' "$w/seq.json"; then
  ok "a dev worker already in the inventory is replaced by the box's address, once"
else bad "a dev worker in the inventory and the box's extra source are not joined cleanly"; cat "$w/out"; fi
# Extra sources with no backup target in the inventory: refused, so the firewall apply fails and the box's wrapper writes no marker (the check ran
# before only when the target was set, and the extra source was dropped silently).
if check "$(sub 'del d["opnsense_lab_backup_target"]; d["opnsense_lab_backup_target_extra_sources"]=[{"name": "dev worker", "address": "192.0.2.30", "vlan": 30}]')"; then
  bad "extra sources with no backup target: the check passed"
elif grep -q "opnsense_lab_backup_target_extra_sources is set but opnsense_lab_backup_target is not" "$w/out"; then ok "extra sources with no backup target are refused"
else bad "extra sources with no backup target: failed some other way"; cat "$w/out"; fi
check "$(sub 'del d["opnsense_lab_backup_target"]')" && ok "no target and no extra sources still passes" || { bad "no target and no extra sources failed"; cat "$w/out"; }
refuse "an extra source with an unknown VLAN is refused" "$(sub 'd["opnsense_lab_backup_target_extra_sources"]=[{"name": "dev worker", "address": "192.0.2.30", "vlan": 99}]')"
refuse "two extra sources with one name are refused" "$(sub 'd["opnsense_lab_backup_target_extra_sources"]=[{"name": "dev worker", "address": "192.0.2.30", "vlan": 30}, {"name": "dev worker", "address": "192.0.2.31", "vlan": 30}]')"
refuse "an extra source that is not an address is refused" "$(sub 'd["opnsense_lab_backup_target_extra_sources"]=[{"name": "dev worker", "address": "192.0.2.0/24", "vlan": 30}]')"
refuse "an extra source beyond the sequences is refused" "$(sub 'd["opnsense_lab_backup_target_extra_sources"]=[{"name": "dev worker", "address": "192.0.2.30", "vlan": 30}]; d["opnsense_lab_backup_target_sequences"]=[13, 14]')"
refuse "a source VLAN tag not in the file is refused" "$(sub 'd["opnsense_lab_backup_target"]["sources"].append({"name": "dev worker", "address": "192.0.2.30", "vlan": 99})')"

# The rule as written: tcp 22 only, /32 at both ends, the sources' VLAN, pass, quick.
python3 -I - "$role/tasks/backup_target.yml" <<'PY' && ok "the rule opens tcp 22 only, from each node's /32 to the host's /32" || bad "the rule task is not as narrow as it should be"
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1]))
r = next(t for t in tasks if t.get("name") == "The c1 nodes to the Proxmox host's ssh")["oxlorg.opnsense.rule"]
assert r["action"] == "pass" and r["quick"] is True and r["direction"] == "in", r
assert r["protocol"] == "TCP" and r["destination_port"] == "22", r
assert r["source_net"] == "{{ item.address }}/32", r
assert r["destination_net"] == "{{ opnsense_lab_backup_target.host }}/32", r
assert "item.vlan | default(opnsense_lab_backup_target.vlan)" in r["interface"][0], r
gone = next(t for t in tasks if t.get("name") == "No rules for backup sources that are gone")["oxlorg.opnsense.rule"]
assert gone["state"] == "absent" and gone["description"] == "Allow {{ item }} to Proxmox backup SSH", gone
PY

[[ $fail -eq 0 ]] && echo "opnsense backup target: all checks passed" || { echo "opnsense backup target: a check failed"; exit 1; }
