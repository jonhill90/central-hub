#!/usr/bin/env bash
# What the restore task hands c1-restore-volumes.sh in RESTORE_SKIP_CLAIMS, run for real with ansible-playbook: the task is lifted out of
# roles/k8s_backup/tasks/restore.yml by name and run against one local stand-in node with a stub script that records its environment.
#   1. A dev run (k8s_backup_restore_own_env unset or false): the skip list reaches the script, space separated.
#   2. Prod's own rebuild (k8s_backup_restore_own_env true, which only rebuild-prod.sh sets): the variable is empty, whatever the list holds.
# Usage: .github/hosts-check/tests/test_restore_skip_env.sh   (needs ansible-playbook and python3 with PyYAML)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
python3 -I - hosts/ansible/roles/k8s_backup/tasks/restore.yml "$t" <<'P' || { echo "FAIL: could not lift the task"; exit 1; }
import sys, yaml
f, t = sys.argv[1:3]
name = "restore | Restore and check each folder"
got = [x for x in yaml.safe_load(open(f)) if x.get("name") == name]
assert len(got) == 1, [x.get("name") for x in yaml.safe_load(open(f))]
task = got[0]
task.pop("when", None)
play = [{"hosts": "k8s_nodes", "gather_facts": False, "tasks": [task]}]
yaml.safe_dump(play, open(f"{t}/play.yml", "w"))
open(f"{t}/inv.ini", "w").write("[k8s_nodes]\nn1 ansible_connection=local\n[k8s_control_plane]\nn1\n")
P
mkdir -p "$t/bin"
printf '#!/bin/sh\nprintf "[%%s]" "$RESTORE_SKIP_CLAIMS" > "%s/seen"\necho "PASS: stub"\n' "$t" > "$t/bin/c1-restore-volumes.sh"
chmod +x "$t/bin/c1-restore-volumes.sh"
run() { # <extra vars>
  rm -f "$t/seen"
  ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False ansible-playbook -i "$t/inv.ini" "$t/play.yml" \
    -e "k8s_backup_bin_dir=$t/bin k8s_backup_node_env_file=/dev/null k8s_backup_state_dir=$t/state k8s_backup_restore_source_host=src k8s_backup_restore_path=/x k8s_backup_restore_snapshot=latest" \
    -e '{"k8s_backup_restore_skip_claims": ["a/one", "b/two"]}' "$@" > "$t/out" 2>&1
}
if run; then [ "$(cat "$t/seen")" = "[a/one b/two]" ] && ok "1 a dev run hands the script the skip list" || bad "1 the script saw $(cat "$t/seen")"; else bad "1 the task failed"; tail -15 "$t/out"; fi
if run -e k8s_backup_restore_own_env=false; then [ "$(cat "$t/seen")" = "[a/one b/two]" ] && ok "1 own_env false too" || bad "1 own_env false: the script saw $(cat "$t/seen")"; else bad "1 own_env false: the task failed"; tail -15 "$t/out"; fi
if run -e k8s_backup_restore_own_env=true; then [ "$(cat "$t/seen")" = "[]" ] && ok "2 prod's own rebuild hands the script an empty skip list" || bad "2 own_env true: the script saw $(cat "$t/seen")"; else bad "2 own_env true: the task failed"; tail -15 "$t/out"; fi
exit $fail
