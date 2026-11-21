#!/usr/bin/env bash
# The agent box role installs the inventory wrapper's list (editable-values.yml) into the wrapper folder. On a fresh box that
# folder does not exist until the role's "Wrapper folder" task makes it, so the copy must come after it (a review of #837
# found it before: "Destination directory ... does not exist"). This test:
#   1. checks the order in tasks/main.yml: no task before the folder task touches the wrapper folder (the handoff script's copy did, since
#      #791), the list's copy comes after it, and no task file included before it (proxmox_host, guard_job, inventory_job) writes under it;
#   2. runs the folder task and the copy task for real into an empty temp folder (a fresh box in miniature): the file is there, mode 0644;
#   3. runs the two copy tasks without the folder task into an empty temp folder and expects the failure (the test's own proof that it would catch the old order).
# Usage: .github/hosts-check/tests/test_inventory_wiring.sh   (needs ansible-playbook and python3 with PyYAML)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
role=$root/hosts/ansible/roles/agent_box

python3 -I - "$role" <<'PY' && ok "1. no task before the wrapper folder task touches the wrapper folder, the list's copy comes after it, and no early task file writes under it" || bad "1. a task before the wrapper folder task touches the wrapper folder, or the list's copy is not after it"
import sys, yaml
role = sys.argv[1]
tasks = yaml.safe_load(open(role + "/tasks/main.yml"))
names = [x.get("name", "") for x in tasks]
folder = names.index("Wrapper folder, root's")
early = [n for x, n in zip(tasks[:folder], names) if "agent_box_libexec_dir" in yaml.dump(x)]
for x in tasks[:folder]:   # a task file included before the folder exists must not write under it either
    inc = x.get("ansible.builtin.include_tasks")
    if inc:
        early += [inc["file"] + ": " + y.get("name", "") for y in yaml.safe_load(open(role + "/tasks/" + inc["file"])) if "agent_box_libexec_dir" in yaml.dump(y)]
copy = next(i for i, n in enumerate(names) if "reviewed list of values a session may set" in n)
handoff = next(i for i, n in enumerate(names) if n.startswith("The handoff script, root-owned"))
for e in early: print("  before the folder task: " + e, file=sys.stderr)
sys.exit(0 if folder < copy and folder < handoff and not early else 1)
PY

# A fresh box in miniature: the repository's tree shape under a temp folder, so playbook_dir finds the list.
mkdir -p "$t/hosts/ansible/playbooks" "$t/hosts/ansible/inventories/home"
cp "$root/hosts/ansible/inventories/home/editable-values.yml" "$t/hosts/ansible/inventories/home/"
build() { # <playbook> <with the folder task: 1|0>
  python3 -I - "$role/tasks/main.yml" "$1" "$2" "$t/libexec" "$role/files" <<'PY'
import sys, yaml
src, out, with_folder, libexec = sys.argv[1:5]
tasks = yaml.safe_load(open(src))
pick = lambda prefix: next(x for x in tasks if x.get("name", "").startswith(prefix))
chosen = ([pick("Wrapper folder, root's")] if with_folder == "1" else []) + [pick("The handoff script, root-owned"), pick("The reviewed list of values a session may set")]
for x in chosen:
    if "ansible.builtin.copy" in x and x["ansible.builtin.copy"].get("src") == "dev-worker-address.sh":
        x["ansible.builtin.copy"]["src"] = sys.argv[5] + "/dev-worker-address.sh"
for x in chosen:
    for mod in ("ansible.builtin.file", "ansible.builtin.copy"):
        if mod in x:
            x[mod].pop("owner", None); x[mod].pop("group", None)   # a test run is not root
    x.pop("tags", None); x.pop("register", None)
yaml.safe_dump([{"hosts": "localhost", "gather_facts": False, "vars": {"agent_box_libexec_dir": libexec}, "tasks": chosen}], open(out, "w"))
PY
}
build "$t/hosts/ansible/playbooks/ok.yml" 1
if ansible-playbook -c local -i localhost, "$t/hosts/ansible/playbooks/ok.yml" >"$t/ok.log" 2>&1 && [ "$(stat -c %a "$t/libexec/editable-values.yml")" = 644 ] \
   && cmp -s "$t/libexec/editable-values.yml" "$root/hosts/ansible/inventories/home/editable-values.yml" \
   && [ "$(stat -c %a "$t/libexec/dev-worker-address.sh")" = 755 ] && cmp -s "$t/libexec/dev-worker-address.sh" "$role/files/dev-worker-address.sh"; then
  ok "2. on an empty box the folder task and then the handoff script and the list copies put both in place (modes 0755 and 0644)"
else bad "2. the real run did not install the list: $(tail -5 "$t/ok.log")"; fi
rm -rf "$t/libexec"
build "$t/hosts/ansible/playbooks/old.yml" 0
if ansible-playbook -c local -i localhost, "$t/hosts/ansible/playbooks/old.yml" >"$t/old.log" 2>&1; then
  bad "3. the copy alone should fail on an empty box, so the test would not catch the old order"
else grep -q 'does not exist' "$t/old.log" && ok "3. the copies without the folder task fail on an empty box with 'does not exist' (the old order)" || bad "3. the copy alone failed for another reason: $(tail -3 "$t/old.log")"; fi
exit "$fail"
