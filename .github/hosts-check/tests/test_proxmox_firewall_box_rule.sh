#!/usr/bin/env bash
# The host firewall's template (hosts/ansible/roles/proxmox_firewall/templates/host.fw.j2) and the role's checks, with python's jinja2:
#   1. With no proxmox_firewall_box_ssh_source the file holds exactly the rules it held before (no box line).
#   2. With one address it adds one line, IN ACCEPT from that address alone, tcp 22, after every other rule, and nothing else changes.
#   3. The role's assert accepts an empty value or one IPv4 address and nothing else (the match in tasks/main.yml).
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)
role=$src/hosts/ansible/roles/proxmox_firewall
python3 - "$role" <<'PY'
import re, sys
try:
    import jinja2
except ImportError:
    print("FAIL jinja2 is not installed: the template test cannot run"); sys.exit(1)
role = sys.argv[1]
tpl = open(role + "/templates/host.fw.j2").read()
env = jinja2.Environment(trim_blocks=True, keep_trailing_newline=True)
env.filters["bool"] = bool
base = dict(proxmox_firewall_enable=True, proxmox_firewall_conntrack_allow_invalid=True, proxmox_firewall_log_level_in="nolog",
            proxmox_firewall_rules=[{"action": "ACCEPT", "source": "+management", "proto": "tcp", "dport": "22", "comment": "ssh"}],
            proxmox_firewall_extra_rules=[{"action": "ACCEPT", "source": "10.9.9.9", "proto": "tcp", "dport": "8006", "comment": "x"}])
none = env.from_string(tpl).render(proxmox_firewall_box_ssh_source="", **base)
one = env.from_string(tpl).render(proxmox_firewall_box_ssh_source="10.1.30.31", **base)
assert "restic sftp from the agent box" not in none, none
extra = [l for l in one.splitlines() if l not in none.splitlines()]
assert extra == ["IN ACCEPT -source 10.1.30.31 -p tcp -dport 22 # restic sftp from the agent box (boxbackup only)"], extra
assert one.splitlines()[-1] == extra[0], "the box rule is not last"
assert [l for l in none.splitlines() if l not in one.splitlines()] == []
print("ok   1-2 no value: no box line; one address: exactly one line, from that address alone, tcp 22, last")
rd = env.from_string(tpl).render(proxmox_firewall_box_ssh_source="10.1.30.31", proxmox_firewall_reader_ssh_source="10.1.30.12", **base)
extra = [l for l in rd.splitlines() if l not in one.splitlines()]
assert extra == ["IN ACCEPT -source 10.1.30.12 -p tcp -dport 22 # restic sftp read-only from the dev worker (c1restore only)"], extra
assert [l for l in one.splitlines() if l not in rd.splitlines()] == []
none2 = env.from_string(tpl).render(proxmox_firewall_box_ssh_source="", proxmox_firewall_reader_ssh_source="", **base)
assert none2 == none, "an empty reader value changed the file"
print("ok   2b a dev worker address: exactly one more line, from that address alone, tcp 22; empty: no line")
main = open(role + "/tasks/main.yml").read()
m = re.search(r"proxmox_firewall_box_ssh_source == '' or proxmox_firewall_box_ssh_source is match\('([^']+)'\)", main)
assert m, "the role's assert is missing"
pat = m.group(1).replace("\\\\", "\\")
good = ["10.1.30.31", "1.2.3.4"]
bad = ["10.1.30.31/32", "10.1.30.31,10.1.30.32", "abc", "10.1.30", " 10.1.30.31", "10.1.30.31\n#x", "any"]
assert all(re.match(pat, g) for g in good), "a good address is refused"
assert not any(re.match(pat, b + "") and not b.endswith("\n#x") for b in bad), "a bad value is accepted"
print("ok   3 the role's check accepts one IPv4 address and refuses ranges, lists, text and a comment")
assert "proxmox_firewall_reader_ssh_source == '' or proxmox_firewall_reader_ssh_source is match('" + m.group(1) + "')" in main, "the reader's assert is missing"
print("ok   3b the role checks the dev worker address with the same match")
PY
