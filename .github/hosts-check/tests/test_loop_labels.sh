#!/usr/bin/env bash
# check-loop-labels.py: every looped task in the agent_box role that writes a file at a path built from its item labels
# each item with that path. 1. The role passes. 2. A looped copy with no label fails, and one with a different label
# fails. 3. The same task with its destination as the label passes.
# Usage: .github/hosts-check/tests/test_loop_labels.sh   (needs python3 with PyYAML)
set -euo pipefail
cd "$(dirname "$0")/../../.."
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
chk=.github/hosts-check/check-loop-labels.py
python3 -I "$chk" hosts/ansible/roles/agent_box/tasks >/dev/null && echo "ok   1. the role's looped file tasks are labelled with their destination" \
  || { echo "FAIL 1: $(python3 -I "$chk" hosts/ansible/roles/agent_box/tasks)"; exit 1; }
task() { # label-lines
  cat > "$t/x.yml" <<EOF
- name: A looped copy
  ansible.builtin.copy:
    src: "{{ item }}"
    dest: "/usr/local/libexec/agent-box/{{ item }}"
  loop: [a.sh, b.sh]
$1
EOF
}
task ""
python3 -I "$chk" "$t" >/dev/null && { echo "FAIL 2a: a looped copy with no label passed"; exit 1; } || echo "ok   2a. a looped copy with no label fails"
task $'  loop_control:\n    label: "{{ item }}"'
python3 -I "$chk" "$t" >/dev/null && { echo "FAIL 2b: a label that is not the destination passed"; exit 1; } || echo "ok   2b. a label that is not the destination fails"
task $'  loop_control:\n    label: "/usr/local/libexec/agent-box/{{ item }}"'
python3 -I "$chk" "$t" >/dev/null && echo "ok   3. the destination as the label passes" || { echo "FAIL 3"; exit 1; }
echo "loop labels: all checks passed"
