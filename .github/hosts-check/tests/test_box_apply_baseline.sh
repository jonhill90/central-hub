#!/usr/bin/env bash
# box-apply's baseline tasks (hosts/ansible/roles/agent_box/tasks/self_apply_baseline.yml, D-0036), run by Ansible in
# check mode from a throwaway clone of this repository:
#   1. A full run from a clean checkout passes every test the baseline needs ("Say why" is skipped).
#   2. An untracked file outside what the role reads (a private inventory file, a tofu lock file) still counts as clean.
#   3. An untracked file in the role, or a change to a tracked file, is not clean.
#   4. --tags and --start-at-task write no baseline.
# Usage: .github/hosts-check/tests/test_box_apply_baseline.sh   (needs git and ansible-playbook)
set -euo pipefail
cd "$(dirname "$0")/../../.."
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0

git clone -q . "$t/repo"
if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
  # Test the working tree as it is, not only the last commit.
  git diff HEAD | git -C "$t/repo" apply --whitespace=nowarn
  git -C "$t/repo" -c user.name=t -c user.email=t@example.invalid commit -qam "working tree"
fi
a=$t/repo/hosts/ansible
cat > "$a/playbooks/baseline-test.yml" <<'EOF'
- name: Baseline test
  hosts: localhost
  gather_facts: false
  vars: {agent_box_self_apply_commit: "", agent_box_self_applying: false}
  tasks:
    - name: First task
      ansible.builtin.set_fact: {agent_box_box_apply_from_start: true}
      tags: [always]
    - name: Second task
      ansible.builtin.debug: {msg: second}
    - name: The baseline tasks
      ansible.builtin.include_tasks:
        file: ../roles/agent_box/tasks/self_apply_baseline.yml
        apply: {tags: [always]}
      tags: [always]
EOF
echo hosts/ansible/playbooks/baseline-test.yml >> "$t/repo/.git/info/exclude"
run() { (cd "$a" && ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i localhost, -c local --check playbooks/baseline-test.yml "$@" 2>&1); }
says_why() { grep -A1 'TASK \[Say why no baseline is written\]' <<<"$1" | grep -q '^ok:'; }

out=$(run)
says_why "$out" && bad "1: $(grep -A2 'Say why' <<<"$out")" || ok "1. a full run from a clean checkout passes every test"
touch "$a/inventories/home/group_vars/private.yml" "$t/repo/hosts/terraform/home/.terraform.lock.hcl"
out=$(run)
says_why "$out" && bad "2: $(grep -A2 'Say why' <<<"$out")" || ok "2. untracked files the role doesn't read leave it clean"
touch "$a/roles/agent_box/tasks/extra.yml"
out=$(run)
says_why "$out" && grep -q 'roles/agent_box/tasks/extra.yml' <<<"$out" && ok "3a. an untracked file in the role is not clean" || bad "3a"
rm "$a/roles/agent_box/tasks/extra.yml"
echo "#" >> "$t/repo/README.md"
out=$(run)
says_why "$out" && grep -q 'M README.md' <<<"$out" && ok "3b. a changed tracked file is not clean" || bad "3b"
git -C "$t/repo" checkout -q README.md
out=$(run --tags never_used)
says_why "$out" && ok "4a. a --tags run writes no baseline" || bad "4a"
out=$(run --start-at-task 'Second task')
says_why "$out" && grep -q 'from the first task False' <<<"$out" && ok "4b. a --start-at-task run writes no baseline" || bad "4b"

[[ $fail == 0 ]] || exit 1
echo "box-apply baseline: all checks passed"
