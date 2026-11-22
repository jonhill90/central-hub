#!/usr/bin/env bash
# The restore's forget hold, run for real with ansible-playbook (not read as text): the two tasks are lifted out of
# roles/k8s_backup/tasks/restore.yml and restore_check.yml by name and run against two local stand-in nodes.
#   1. With no state folder on the nodes (the role's install tags never ran there) the hold task makes the folder (0700) and the
#      forget-hold file (0600) on every node.
#   2. The release task removes the file on every node, and passes again with the file and the folder already gone.
# Usage: .github/hosts-check/tests/test_restore_hold.sh   (needs ansible-playbook and python3 with PyYAML)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
role=hosts/ansible/roles/k8s_backup/tasks
python3 -I - "$role" "$t" <<'P' || { echo "FAIL: could not lift the tasks"; exit 1; }
import sys, yaml
role, t = sys.argv[1:3]
def pick(f, names):
    tasks = yaml.safe_load(open(f"{role}/{f}"))
    got = [x for x in tasks if x.get("name") in names]
    assert len(got) == len(names), (f, names, [x.get("name") for x in got])
    return got
hold = pick("restore.yml", ["restore | The hold's folder exists on every node", "restore | Hold every node's forget until the restore is proven"])
rel = pick("restore_check.yml", ["restore_check | Release every node's forget hold"])
for name, tasks in (("hold", hold), ("release", rel)):
    play = [{"hosts": "k8s_nodes", "gather_facts": False,
             "vars": {"k8s_backup_state_dir": f"{t}/state"}, "tasks": tasks}]
    yaml.safe_dump(play, open(f"{t}/{name}.yml", "w"))
open(f"{t}/inv.ini", "w").write("[k8s_nodes]\nn1 ansible_connection=local\nn2 ansible_connection=local\n")
P
run() { ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ansible-playbook -i "$t/inv.ini" "$t/$1.yml" >"$t/$1.out" 2>&1; }
# the task asks root:root; run as the current user in the test by mapping it
sed -i "s/owner: root/owner: $(id -un)/; s/group: root/group: $(id -gn)/" "$t/hold.yml"
if run hold; then ok "1 hold task runs"; else bad "1 hold task failed"; tail -15 "$t/hold.out"; fi
[ -f "$t/state/forget-hold" ] && ok "1 forget-hold written" || bad "1 forget-hold missing"
[ "$(stat -c %a "$t/state")" = 700 ] && ok "1 folder 0700" || bad "1 folder mode $(stat -c %a "$t/state" 2>/dev/null)"
[ "$(stat -c %a "$t/state/forget-hold" 2>/dev/null)" = 600 ] && ok "1 file 0600" || bad "1 file mode"
sed -i "s/when: ansible_play_hosts_all | length == ansible_play_hosts | length/when: true/" "$t/release.yml"
if run release; then ok "2 release runs"; else bad "2 release failed"; tail -15 "$t/release.out"; fi
[ ! -e "$t/state/forget-hold" ] && ok "2 file removed" || bad "2 file still there"
rm -rf "$t/state"
if run release; then ok "2 release with nothing there passes"; else bad "2 release with no folder failed"; tail -15 "$t/release.out"; fi
exit $fail
