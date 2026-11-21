#!/usr/bin/env bash
# The agent box role installs the inventory wrapper's list (editable-values.yml) into the wrapper folder. On a fresh box that
# folder does not exist until the role's "Wrapper folder" task makes it, so the copy must come after it (a review of #837
# found it before: "Destination directory ... does not exist"). This test:
#   1. checks the order in tasks/main.yml, and that inventory_job.yml writes nothing under the wrapper folder;
#   2. runs the folder task and the copy task for real into an empty temp folder (a fresh box in miniature): the file is there, mode 0644;
#   3. runs the copy task alone into an empty temp folder and expects the failure (the test's own proof that it would catch the old order).
# Usage: .github/hosts-check/tests/test_inventory_wiring.sh   (needs ansible-playbook and python3 with PyYAML)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
role=$root/hosts/ansible/roles/agent_box

python3 -I - "$role" <<'PY' && ok "1. the list's copy comes after the wrapper folder task, and inventory_job.yml writes nothing under the wrapper folder" || bad "1. wrong order, or inventory_job.yml writes under the wrapper folder"
import sys, yaml
role = sys.argv[1]
names = [x.get("name", "") for x in yaml.safe_load(open(role + "/tasks/main.yml"))]
folder = names.index("Wrapper folder, root's")
copy = next(i for i, n in enumerate(names) if "reviewed list of values a session may set" in n)
job = yaml.safe_load(open(role + "/tasks/inventory_job.yml"))
under = [x["name"] for x in job if "libexec" in yaml.dump(x)]
sys.exit(0 if folder < copy and not under else 1)
PY

# A fresh box in miniature: the repository's tree shape under a temp folder, so playbook_dir finds the list.
mkdir -p "$t/hosts/ansible/playbooks" "$t/hosts/ansible/inventories/home"
cp "$root/hosts/ansible/inventories/home/editable-values.yml" "$t/hosts/ansible/inventories/home/"
build() { # <playbook> <with the folder task: 1|0>
  python3 -I - "$role/tasks/main.yml" "$1" "$2" "$t/libexec" <<'PY'
import sys, yaml
src, out, with_folder, libexec = sys.argv[1:5]
tasks = yaml.safe_load(open(src))
pick = lambda prefix: next(x for x in tasks if x.get("name", "").startswith(prefix))
chosen = ([pick("Wrapper folder, root's")] if with_folder == "1" else []) + [pick("The reviewed list of values a session may set")]
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
   && cmp -s "$t/libexec/editable-values.yml" "$root/hosts/ansible/inventories/home/editable-values.yml"; then
  ok "2. on an empty box the folder task and then the copy put the list in place, mode 0644"
else bad "2. the real run did not install the list: $(tail -5 "$t/ok.log")"; fi
rm -rf "$t/libexec"
build "$t/hosts/ansible/playbooks/old.yml" 0
if ansible-playbook -c local -i localhost, "$t/hosts/ansible/playbooks/old.yml" >"$t/old.log" 2>&1; then
  bad "3. the copy alone should fail on an empty box, so the test would not catch the old order"
else grep -q 'does not exist' "$t/old.log" && ok "3. the copy alone fails on an empty box with 'does not exist' (the old order)" || bad "3. the copy alone failed for another reason: $(tail -3 "$t/old.log")"; fi
exit "$fail"
