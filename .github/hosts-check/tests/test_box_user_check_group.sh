#!/usr/bin/env bash
# The agent box role's three user tasks that put a system user in the handoff group (keys user in main.yml, the
# guard job's user, the Proxmox host job's user), run with `ansible-playbook --check` on a machine that has no such
# group yet (a made-up group; the existing user nobody stands in for the role's users, which are on the box already):
#   1. The group task reports changed and the user task does not fail, and it reports changed (so box-apply
#      predicts the limit user and the real run may change it).
#   2. The same task without the fix fails with "Group ... does not exist" (the test's own proof that it tests it).
#   3. Another failure in a check run still fails (a different missing group, not the role's handoff group).
# Usage: .github/hosts-check/tests/test_box_user_check_group.sh   (needs ansible-playbook and python3 with PyYAML)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
tasks=$root/hosts/ansible/roles/agent_box/tasks
grp=zz-nodevaddr-$$

# build <playbook> <tasks file> <task name prefix> <user name> <strip fix 0|1>
build() {
  python3 -I - "$@" "$grp" <<'PY'
import sys, yaml
out, path, prefix, user, strip, grp = sys.argv[1:7]
tasks = yaml.safe_load(open(path))
task = next(x for x in tasks if x.get("name", "").startswith(prefix))
group_task = {"name": "group", "ansible.builtin.group": {"name": grp, "system": True}}
mod = task["ansible.builtin.user"]
mod["name"] = "{{ item }}" if strip != "1" else user
if strip != "1":
    task["loop"] = ["nobody" if user == "other" else user]
    task["loop_control"] = {"label": "{{ item }}"}
mod.pop("home", None)
mod.pop("create_home", None)
mod["groups"] = grp if user != "other" else grp + "-other"
if user == "other":
    mod["name"] = "nobody"
if strip == "1":
    for k in ("register", "failed_when", "changed_when", "loop", "loop_control"):
        task.pop(k, None)
    play_tasks = [group_task, task]
else:
    play_tasks = [group_task, task]
play = [{"hosts": "localhost", "connection": "local", "gather_facts": False,
         "vars": {"agent_box_devaddr_group": grp}, "tasks": play_tasks}]
yaml.safe_dump(play, open(out, "w"))
PY
}
run() { ANSIBLE_NOCOLOR=1 ansible-playbook -i localhost, "$1" --check 2>&1 || true; }
summary() {  # the default output, one line per task: "<task name> failed|changed|ok"
  python3 -I -c '
import re, sys
name = None
for line in sys.stdin:
    m = re.match(r"TASK \[(.*)\]", line)
    if m:
        name = m.group(1)
        continue
    m = re.match(r"(ok|changed|fatal|failed): \[localhost\]", line)
    if m and name:
        print(name[:30], {"ok": "ok", "changed": "changed", "fatal": "failed", "failed": "failed"}[m.group(1)])
        name = None
'
}
case_for() {  # file, prefix, label
  build "$t/p.yml" "$tasks/$1" "$2" nobody 0
  s=$(run "$t/p.yml" | summary)
  if grep -q "^$2.* changed$" <<<"$s" && ! grep -q failed <<<"$s"; then ok "1. $3: the user task reports changed in a check run, group missing"; else bad "1. $3: $s"; fi
  build "$t/q.yml" "$tasks/$1" "$2" nobody 1
  s=$(run "$t/q.yml" | summary)
  if grep -q failed <<<"$s"; then ok "2. $3: without the fix the same task fails"; else bad "2. $3: expected a failure: $s"; fi
}
case_for main.yml "Keys user" "keys user"
case_for guard_job.yml "guard_job | The jobs' user" "guard job user"
case_for proxmox_host.yml "proxmox_host | The job's user" "host job user"
# 3. another failure still fails: a missing group that is not the handoff group
build "$t/r.yml" "$tasks/main.yml" "Keys user" other 0
s=$(run "$t/r.yml" | summary)
if grep -q "^Keys user.* failed$" <<<"$s"; then ok "3. another failure in a check run still fails"; else bad "3. $s"; fi

# 4. box-apply reads the masked result: it names the limit user from the loop label (so the apply may change it)
#    and flags it as a limit change; and a failed run's message names the failed tasks, names only.
python3 -I - "$root/hosts/ansible/roles/agent_box/files/box-apply.py" <<'PY' && ok "4. box-apply predicts the user of a masked result and names failed tasks" || bad "4. box-apply"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("box_apply", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
rules = {"path": [], "except": [], "free-keys": {}, "box": [], "dir": [], "user": ["keysuser"]}
masked = {"msg": "Group x does not exist", "changed": True, "failed_when_result": False, "item": "keysuser",
          "_ansible_item_label": "keysuser"}
out = {"plays": [{"tasks": [
    {"task": {"name": "Keys user"}, "hosts": {"h": {"changed": True, "results": [masked]}}},
    {"task": {"name": "A broken one"}, "hosts": {"h": {"failed": True, "msg": "secret value"}}}]}]}
assert m.predicted(rules, out) == {"keysuser"}, m.predicted(rules, out)
assert m.check_hits(rules, out) == ["Keys user: user keysuser"], m.check_hits(rules, out)
note = m.failed_note(out)
assert note == " Failed tasks: A broken one.", note
assert "secret" not in note and m.failed_note({"plays": []}) == ""
PY
exit $fail
