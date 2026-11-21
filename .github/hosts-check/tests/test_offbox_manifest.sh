#!/usr/bin/env bash
# The manifest the role writes (backend-files.sha256, tasks/offbox_scripts.yml) must equal sha256sum of the installed scripts, byte for byte.
# The file lookup strips a trailing newline unless rstrip=false, which would make box-prove and rebuild-prod.sh check fail on a correct box.
# This renders the role's own manifest task with a real ansible run (a one-task role in a temp folder, files/ the role's real scripts) and
# compares each line with sha256sum of the script. A manifest that hashes the script without its last newline fails here.
# Usage: .github/hosts-check/tests/test_offbox_manifest.sh   (needs ansible-playbook, python3 with PyYAML)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
src=$PWD/hosts/ansible/roles/agent_box
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
mkdir -p "$t/roles/r/tasks" "$t/roles/r/files" "$t/out"
for f in opnsense-offbox.sh secrets-bundle-offbox.sh; do cp "$src/files/$f" "$t/roles/r/files/$f"; done
python3 -I - "$src/tasks/offbox_scripts.yml" "$t/roles/r/tasks/main.yml" <<'PY'
import sys, yaml
tasks = [x for x in yaml.safe_load(open(sys.argv[1])) if "backend-files.sha256" in str(x)]
assert len(tasks) == 1, "one manifest task"
# the content is what is under test; the owner is root on the box and a runner cannot chown
for k in ("owner", "group"):
    tasks[0]["ansible.builtin.copy"].pop(k, None)
yaml.safe_dump(tasks, open(sys.argv[2], "w"))
PY
printf -- '- hosts: localhost\n  connection: local\n  gather_facts: false\n  vars:\n    agent_box_libexec_dir: %s\n  roles: [r]\n' "$t/out" > "$t/pb.yml"
ANSIBLE_ROLES_PATH=$t/roles ANSIBLE_HOME=$t/home ansible-playbook -i localhost, "$t/pb.yml" > "$t/ansible.out" 2>&1 || { bad "the manifest task did not render: $(tail -5 "$t/ansible.out")"; exit 1; }
# each manifest line is the sha256 of the script file, and sha256sum -c accepts it
( cd "$t/out" && cp "$t/roles/r/files/"*.sh . && sha256sum -c backend-files.sha256 > "$t/check.out" 2>&1 ) \
  && ok "1 sha256sum -c accepts the rendered manifest for both scripts: $(tr '\n' ' ' < "$t/check.out")" || bad "1 the manifest differs from sha256sum: $(cat "$t/check.out")"
[[ $(wc -l < "$t/out/backend-files.sha256") == 2 ]] && ok "2 the manifest has two lines" || bad "2 manifest lines: $(cat "$t/out/backend-files.sha256")"
exit "$fail"
