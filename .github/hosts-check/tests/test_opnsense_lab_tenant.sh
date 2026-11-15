#!/usr/bin/env bash
# The opnsense_lab role's tenant VLAN keys, offline (no firewall, no API):
#   1. With no VLAN using the new keys, the lists the rules are built from are today's: the management
#      VLAN passes into the three other VLANs (sequences 5 to 7) and no VLAN is kept off the tailnet.
#   2. With the real VLAN file (tenant, tailnet: false) and its settings (mgmt_pass: false), the
#      management passes are still those three, only tenant is kept off the tailnet, and its
#      tailnet block rule (sequence 195) sits before its internet rule (200).
#   3. A VLAN with tailnet: false and no mgmt_pass in its settings fails the role's check, and the
#      check is tagged always, so a run limited with --tags rules still runs it.
#   4. The tailnet connector's advertised routes, from the real VLAN file, leave out VLAN 60 and keep
#      the VLANs that have no tailnet key (a test on the missing key once broke every run).
# Usage: .github/hosts-check/tests/test_opnsense_lab_tenant.sh   (needs ansible-core)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
role=$root/hosts/ansible/roles/opnsense_lab
vlan_file=$root/hosts/ansible/inventories/home/group_vars/all/vlans.yml
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

cat > "$w/old.yml" <<'YML'
lab_vlans:
  - { id: 10, name: prod, alias: prod, cidr: 10.1.10.0/24 }
  - { id: 20, name: qa, alias: qa and stage, cidr: 10.1.20.0/24 }
  - { id: 30, name: dev, alias: dev, cidr: 10.1.30.0/24 }
  - { id: 50, name: mgmt, alias: management, cidr: 10.1.50.0/24 }
opnsense_lab_vlan_settings:
  prod: { ifname: opt1, dhcp: true, bootstrap: false }
  qa: { ifname: opt2, dhcp: false, bootstrap: false }
  dev: { ifname: opt3, dhcp: true, bootstrap: false }
  mgmt: { ifname: lan, dhcp: false, bootstrap: true }
opnsense_lab_mgmt_tag: 50
YML
cat > "$w/settings-tenant.yml" <<'YML'
opnsense_lab_vlan_settings:
  prod: { ifname: opt1, dhcp: true, bootstrap: false }
  qa: { ifname: opt2, dhcp: false, bootstrap: false }
  dev: { ifname: opt3, dhcp: true, bootstrap: false }
  mgmt: { ifname: lan, dhcp: false, bootstrap: true }
  tenant: { ifname: opt4, dhcp: true, bootstrap: false, mgmt_pass: false }
opnsense_lab_mgmt_tag: 50
YML
cat > "$w/settings-no-mgmt-pass.yml" <<'YML'
opnsense_lab_vlan_settings:
  prod: { ifname: opt1, dhcp: true, bootstrap: false }
  qa: { ifname: opt2, dhcp: false, bootstrap: false }
  dev: { ifname: opt3, dhcp: true, bootstrap: false }
  mgmt: { ifname: lan, dhcp: false, bootstrap: true }
  tenant: { ifname: opt4, dhcp: true, bootstrap: false }
opnsense_lab_mgmt_tag: 50
YML

cat > "$w/baseline.yml" <<YML
- hosts: localhost
  gather_facts: false
  vars_files: ["$w/old.yml", "$role/vars/main.yml"]
  tasks:
    - ansible.builtin.assert:
        that:
          - opnsense_lab_mgmt_pass_vlans | map(attribute='tag') | list == [10, 20, 30]
          - opnsense_lab_mgmt_no_pass_vlans | length == 0
          - opnsense_lab_tailnet_off_vlans | length == 0
          - (range(5, 5 + (opnsense_lab_mgmt_pass_vlans | length)) | list) == [5, 6, 7]
          - (opnsense_lab_vlans | map(attribute='tag') | list) == [10, 20, 30, 50]
YML
cat > "$w/tenant.yml" <<YML
- hosts: localhost
  gather_facts: false
  vars_files: ["$vlan_file", "$w/settings-tenant.yml", "$role/vars/main.yml"]
  tasks:
    - ansible.builtin.assert:
        that:
          - opnsense_lab_mgmt_pass_vlans | map(attribute='tag') | list == [10, 20, 30]
          - opnsense_lab_mgmt_no_pass_vlans | map(attribute='tag') | list == [60]
          - opnsense_lab_tailnet_off_vlans | map(attribute='tag') | list == [60]
          - (opnsense_lab_vlans | map(attribute='tag') | list)[-1] == 60
          - 10 + (opnsense_lab_vlans.index(opnsense_lab_tailnet_off_vlans[0]) * 4 + 3) * 10 - 5 == 195
          - 10 + (opnsense_lab_vlans.index(opnsense_lab_tailnet_off_vlans[0]) * 4 + 2) * 10 < 195
          - 10 + (opnsense_lab_vlans.index(opnsense_lab_tailnet_off_vlans[0]) * 4 + 3) * 10 == 200
YML
for t in "good:settings-tenant.yml" "bad:settings-no-mgmt-pass.yml"; do
  name=${t%%:*}; s=${t#*:}
  cat > "$w/checks-$name.yml" <<YML
- hosts: localhost
  gather_facts: false
  vars_files: ["$vlan_file", "$w/$s"]
  tasks:
    - ansible.builtin.import_tasks: $role/tasks/tenant_checks.yml
YML
done

printf "[defaults]\n" > "$w/ansible.cfg"
run() { (cd "$w" && ANSIBLE_CONFIG="$w/ansible.cfg" ansible-playbook -i localhost, -c local "$1" >"$w/out.txt" 2>&1); }
run baseline.yml && ok "no VLAN uses the new keys: management passes 5 to 7 and no tailnet block, as today" || { bad "baseline lists changed"; cat "$w/out.txt"; }
run tenant.yml && ok "tenant: management passes unchanged, tailnet block at 195 before the internet rule at 200" || { bad "tenant lists or sequences wrong"; cat "$w/out.txt"; }
run checks-good.yml && ok "tailnet: false with mgmt_pass set passes the role's check" || { bad "check rejected a complete entry"; cat "$w/out.txt"; }
if run checks-bad.yml; then bad "tailnet: false without mgmt_pass was accepted"
elif grep -q "must set mgmt_pass" "$w/out.txt"; then ok "tailnet: false without mgmt_pass fails the role's check"
else bad "the bad entry failed for another reason"; cat "$w/out.txt"; fi

cat > "$w/connector.yml" <<YML
- hosts: localhost
  gather_facts: false
  vars_files: ["$vlan_file", "$root/hosts/ansible/roles/tailnet_connector/vars/main.yml"]
  vars:
    tailnet_connector_extra_routes: ["192.0.2.10/32"]
  tasks:
    - ansible.builtin.assert:
        that:
          - ((tailnet_connector_extra_routes + tailnet_connector_lab_cidrs) | unique | sort) == ['10.1.10.0/24', '10.1.20.0/24', '10.1.30.0/24', '10.1.50.0/24', '192.0.2.10/32']
YML
run connector.yml && ok "connector routes: VLANs without a tailnet key kept, VLAN 60 left out" || { bad "connector routes wrong"; cat "$w/out.txt"; }

# Skipped by --tags rules unless tagged always: the import in main.yml must carry the tag.
if python3 - "$role/tasks/main.yml" <<'PY'
import sys
from ruamel.yaml import YAML
tasks = YAML(typ="safe", pure=True).load(open(sys.argv[1]))
hit = [t for t in tasks if t.get("ansible.builtin.import_tasks") == "tenant_checks.yml"]
sys.exit(0 if len(hit) == 1 and "always" in hit[0].get("tags", []) else 1)
PY
then ok "tenant_checks.yml is imported with tags: [always]"; else bad "tenant_checks.yml is not tagged always"; fi
exit "$fail"
