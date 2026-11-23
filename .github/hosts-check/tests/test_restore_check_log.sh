#!/usr/bin/env bash
# The restore check's lines reach the rebuild's short log. The task "restore_check | What is in place" is lifted out of
# roles/k8s_backup/tasks/restore_check.yml and run for real with ansible-playbook on a stand-in of c1-restore-volumes.sh check's output
# (the record's lines, indented, and the PASS line with its timestamp). The short log keeps the Ansible-quoted lines that start with
# snapshot, canary, folder or PASS (hosts/rebuild-k8s.sh, the `checks` stage): the PASS line, which says which canary the check
# accepted, and the record's own lines must be among them (prod resume 7, 2026-11-22: they were not, so it was not proven which branch wk-1 took).
# Usage: .github/hosts-check/tests/test_restore_check_log.sh   (needs ansible-playbook and python3 with PyYAML)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
python3 -I - hosts/ansible/roles/k8s_backup/tasks/restore_check.yml "$t" <<'P' || { echo "FAIL: could not lift the task"; exit 1; }
import sys, yaml
f, t = sys.argv[1:3]
task = [x for x in yaml.safe_load(open(f)) if x.get("name") == "restore_check | What is in place"]
assert len(task) == 1
lines = ["   snapshot\tb314a21a\tprod-wk-1\t2026-11-21T08:29:09Z", "   canary\tJ8nk-restore-canary", "   folder\tmedia/jellyfin-config\t2\t100",
         "2026-11-22T08:39:01Z PASS: restore of snapshot b314a21a still in place, 1 folders, canary matches the one the node's own backup recorded after the restore, and the newest volumes snapshot holds it"]
play = [{"hosts": "localhost", "gather_facts": False, "connection": "local",
         "vars": {"k8s_backup_restore_check": {"stdout_lines": lines}}, "tasks": task}]
yaml.safe_dump(play, open(f"{t}/p.yml", "w"))
P
ANSIBLE_LOCALHOST_WARNING=False ansible-playbook -i localhost, "$t/p.yml" > "$t/out" 2>&1 || { cat "$t/out"; bad "the task did not run"; }
# The short log's own filter (the first alternatives of the grep in hosts/rebuild-k8s.sh), run on the output.
kept=$(grep -E '"(snapshot|canary|folder|PASS|RESTORED|ALREADY|SKIP)' "$t/out" | sed -e 's/^ *//')
if [[ $kept == *'"PASS: restore of snapshot b314a21a still in place, 1 folders, canary matches the one the node'* && $kept == *'"canary'*J8nk-restore-canary* &&
      $kept == *'"snapshot'*b314a21a* && $kept == *'"folder'*jellyfin-config* && $kept != *2026-11-22T08* ]]; then
  ok "the short log keeps the check's PASS line (without its timestamp), the snapshot, the canary and the folders"
else bad "the short log lacks the check's lines: [$kept]"; cat "$t/out"; fi
grep -qF "grep -E '\"(snapshot|canary|folder|PASS|RESTORED|ALREADY|SKIP)" hosts/rebuild-k8s.sh && grep -q '\[ "\$s" = checks \]' hosts/rebuild-k8s.sh &&
  ok "hosts/rebuild-k8s.sh filters the checks stage with that grep" || bad "rebuild-k8s.sh no longer filters the checks stage that way"
exit $fail
