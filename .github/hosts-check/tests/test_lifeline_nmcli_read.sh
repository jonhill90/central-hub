#!/usr/bin/env bash
# The lifeline role reads its connection with one `nmcli -g <fields> connection show lifeline` (tasks/lifeline.yml).
# The fields must be ONE argument. A folded YAML line once split them in two at a space after a comma, so nmcli
# failed on every run and "made once", "static, never the default route" and "up on the NIC" reported changed on every apply.
#   1. The read task's command, as Ansible would split it, is nmcli -g <one list> connection show lifeline.
#   2. The field list has no space and names the nine fields the wanted-values list compares.
#   3. The mutation (a space after a comma, as the folded line made it) is caught.
# Usage: .github/hosts-check/tests/test_lifeline_nmcli_read.sh   (needs python3 with PyYAML)
set -euo pipefail
cd "$(dirname "$0")/../../.."
f=hosts/ansible/roles/agent_box/tasks/lifeline.yml
fail=0
check() { python3 -I - "$1" <<'PY'
import shlex, sys, yaml
tasks = yaml.safe_load(open(sys.argv[1]))
t = [x for x in tasks if x["name"].startswith("lifeline | The connection's settings now")][0]
c = t["ansible.builtin.command"]
argv = c["argv"] if isinstance(c, dict) else shlex.split(c)
fields = argv[2].split(",")
wanted = [x for x in tasks if x["name"].startswith("lifeline | The connection is static")][0]["vars"]["agent_box_lifeline_wanted"]
ok = argv[:2] == ["nmcli", "-g"] and argv[3:] == ["connection", "show", "lifeline"] and " " not in argv[2] and len(fields) == 9 == len(wanted) and fields[-2:] == ["connection.autoconnect", "connection.interface-name"]
sys.exit(0 if ok else 1)
PY
}
if check "$f"; then echo "ok   the lifeline read is one nmcli -g argument naming nine fields"; else echo "FAIL the lifeline read is split or short"; fail=1; fi
m=$(mktemp); trap 'rm -f "$m"' EXIT
python3 -I - "$f" "$m" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = "ipv6.method,connection.autoconnect"
assert a in s
open(sys.argv[2], "w").write(s.replace(a, "ipv6.method, connection.autoconnect"))
PY
if check "$m"; then echo "FAIL mutation: a space after a comma passes"; fail=1; else echo "ok   mutation: a space after a comma is caught"; fi
exit $fail
