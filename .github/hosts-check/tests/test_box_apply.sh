#!/usr/bin/env bash
# box-apply (hosts/ansible/roles/agent_box/files/box-apply.py, D-0036), against a local git repository standing in
# for main and a stand-in for ansible-playbook that prints fixed JSON:
#   1. No baseline, a baseline that is not on main, and a wrong argument each refuse.
#   2. A change to free defaults keys and to other files plans and applies, and moves the baseline.
#   3. A change to a limit file, or to a defaults key that is not free, stops before any run.
#   4. A comment-only change in the defaults is not a limit change.
#   5. A check run that would change a limit path on the box stops before the apply.
#   6. An apply that changes limit files on the box is put back, and self-applies stop until the controller
#      ends the stop.
#   7. A failed apply leaves the baseline where it was.
# Usage: .github/hosts-check/tests/test_box_apply.sh   (needs git and python3)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0

# The repository: main with the role's files.
git init -q --bare "$t/origin.git"
git init -q -b main "$t/src"
g() { git -C "$t/src" -c user.name=t -c user.email=t@example.invalid "$@"; }
r=hosts/ansible/roles/agent_box
mkdir -p "$t/src/$r/tasks" "$t/src/$r/defaults" "$t/src/$r/meta" "$t/src/hosts/ansible/playbooks" "$t/src/docs"
printf -- '- name: x\n  ansible.builtin.debug:\n' > "$t/src/$r/tasks/main.yml"
cat > "$t/src/$r/defaults/main.yml" <<'EOF'
---
# The users.
agent_box_user: claude
agent_box_tofu_version: 1.13.1
agent_box_wrappers:
  - name: dev-vms
    args: [plan]
EOF
echo '{}' > "$t/src/$r/meta/argument_specs.yml"
echo '- hosts: agent_box' > "$t/src/hosts/ansible/playbooks/agent-box.yml"
echo '[defaults]' > "$t/src/hosts/ansible/ansible.cfg"
echo one > "$t/src/docs/x.md"
g add -A && g commit -qm c0 && g push -q "$t/origin.git" main 2>/dev/null
c0=$(g rev-parse HEAD)
commit() { g add -A && g commit -qm "$1" && g push -q "$t/origin.git" main 2>/dev/null && g rev-parse HEAD; }

# The box: limit files, a key folder, and box-apply with its paths moved under $t.
mkdir -p "$t/box/sudoers.d" "$t/box/keys" "$t/etc" "$t/state" "$t/bin"
echo 'claude ALL=(keys) NOPASSWD: /x plan' > "$t/box/sudoers.d/agent-box"
chmod 700 "$t/box/keys"
sed -e "s|^SETTINGS = .*|SETTINGS = \"$t/etc/settings.json\"|" -e "s|^LIMITS = .*|LIMITS = \"$t/etc/limits.txt\"|" \
    -e "s|^STATE = .*|STATE = \"$t/state\"|" -e "s|^LOG = .*|LOG = \"$t/box-apply.log\"|" \
    "$root/$r/files/box-apply.py" > "$t/box-apply.py"
grep -q "^STATE = \"$t/state\"" "$t/box-apply.py" || { echo "FAIL the paths were not moved"; exit 1; }
cat > "$t/etc/settings.json" <<EOF
{"repo_url": "file://$t/origin.git", "ansible_playbook": "$t/bin/ansible-playbook", "collections": "$t/coll",
 "inventory": "$t/etc/inventory.yml", "skip_tags": ["ca", "verify"]}
EOF
cat > "$t/etc/limits.txt" <<EOF
# test limits
path $r/*
except $r/defaults/main.yml
except $r/meta/argument_specs.yml
path hosts/ansible/playbooks/agent-box.yml
path hosts/ansible/ansible.cfg
free-keys $r/defaults/main.yml agent_box_tofu_version
box $t/box/sudoers.d/*
dir $t/box/keys
user $(id -un)
EOF
# Stand-in for ansible-playbook: logs its arguments and environment, runs $t/apply-hook on a real run, and
# prints $t/check.json or $t/apply.json; exits with what $t/rc holds.
quiet='{"plays":[{"tasks":[{"task":{"name":"a pinned tool"},"hosts":{"box1":{"changed":true,"dest":"/usr/local/bin/tofu"}}}]}],"stats":{"box1":{"failures":0,"unreachable":0}}}'
echo "$quiet" > "$t/check.json"
echo "$quiet" > "$t/apply.json"
echo 0 > "$t/rc"
cat > "$t/bin/ansible-playbook" <<EOF
#!/bin/bash
echo "\$* | \$ANSIBLE_STDOUT_CALLBACK | \$ANSIBLE_COLLECTIONS_PATH | \$PWD" >> "$t/calls"
if [[ " \$* " == *" --check "* ]]; then cat "$t/check.json"; else [[ -x $t/apply-hook ]] && "$t/apply-hook"; cat "$t/apply.json"; fi
exit "\$(cat $t/rc)"
EOF
chmod +x "$t/bin/ansible-playbook"
ba() { python3 -I "$t/box-apply.py" "$@" 2>&1; }
calls() { [[ -f $t/calls ]] && wc -l < "$t/calls" || echo 0; }
base() { cat "$t/state/baseline" 2>/dev/null; }

# 1
if out=$(ba plan); then bad "no baseline: should stop"; elif [[ $out == *"no baseline"* ]]; then ok "1a. refuses with no baseline"; else bad "1a: $out"; fi
echo 0123456789012345678901234567890123456789 > "$t/state/baseline"
if out=$(ba plan); then bad "foreign baseline: should stop"; elif [[ $out == *"not a commit on main"* ]]; then ok "1b. refuses a baseline that is not on main"; else bad "1b: $out"; fi
set +e; ba apply-now >/dev/null; rc=$?; set -e
[[ $rc == 2 ]] && ok "1c. refuses another argument" || bad "1c: exit $rc"
[[ $(calls) == 0 ]] && ok "1d. none of these ran the role" || bad "1d: the role ran"
echo "$c0" > "$t/state/baseline"

# 2
sed -i 's/^agent_box_tofu_version: .*/agent_box_tofu_version: 1.13.2/' "$t/src/$r/defaults/main.yml"
echo two > "$t/src/docs/x.md"
c1=$(commit c1)
out=$(ba plan) || bad "2a: plan failed: $out"
[[ $out == *"none of them a limit"* && $(calls) == 1 && $(base) == "$c0" ]] && ok "2a. a free change plans with one check run, and the baseline stays" || bad "2a: $out"
grep -q -- "--check --diff" "$t/calls" && grep -q -- "--skip-tags ca,verify -e agent_box_self_applying=true" "$t/calls" \
  && grep -q "ansible.builtin.json | $t/coll | $t/state/central-hub/hosts/ansible" "$t/calls" \
  && ok "2b. the check run skips the tags, marks the run as a self-apply, and runs from its own checkout" || bad "2b: $(cat "$t/calls")"
out=$(ba apply) || bad "2c: apply failed: $out"
[[ $out == *"applied ${c1:0:8}"* && $(base) == "$c1" && $(calls) == 3 ]] && ok "2c. apply runs check then the role, and moves the baseline" || bad "2c: $out"
tail -n 1 "$t/box-apply.log" | grep -q '"result": "applied"' && ok "2d. the run is logged" || bad "2d: $(tail -n 1 "$t/box-apply.log")"

# 3
n=$(calls)
printf -- '- name: y\n  ansible.builtin.debug:\n' >> "$t/src/$r/tasks/main.yml"
c2=$(commit c2)
set +e; out=$(ba apply); rc=$?; set -e
[[ $rc == 3 && $out == *"$r/tasks/main.yml"* && $(calls) == "$n" && $(base) == "$c1" ]] && ok "3a. a change to a limit file stops before any run" || bad "3a: exit $rc: $out"
echo "$c2" > "$t/state/baseline"   # as a full apply from the controller would
sed -i 's/^agent_box_user: .*/agent_box_user: someone/' "$t/src/$r/defaults/main.yml"
c3=$(commit c3)
set +e; out=$(ba plan); rc=$?; set -e
[[ $rc == 3 && $out == *"defaults/main.yml: agent_box_user"* && $(calls) == "$n" ]] && ok "3b. a change to a defaults key that is not free stops" || bad "3b: exit $rc: $out"
sed -i 's/  - name: dev-vms/  - name: dev-vms\n    runner: true/' "$t/src/$r/defaults/main.yml"
echo "$c3" > "$t/state/baseline"
c4=$(commit c4)
set +e; out=$(ba plan); rc=$?; set -e
[[ $rc == 3 && $out == *"agent_box_wrappers"* ]] && ok "3c. a change inside the wrapper list stops" || bad "3c: exit $rc: $out"
echo "$c4" > "$t/state/baseline"

# 4
sed -i 's/^# The users./# The users of the box./' "$t/src/$r/defaults/main.yml"
commit c5 >/dev/null
out=$(ba plan) || bad "4: plan failed: $out"
[[ $out == *"none of them a limit"* ]] && ok "4. a comment-only change in the defaults is not a limit change" || bad "4: $out"

# 5
n=$(calls)
echo '{"plays":[{"tasks":[{"task":{"name":"One sudoers line per wrapper"},"hosts":{"box1":{"changed":true,"diff":[{"before_header":"'"$t"'/box/sudoers.d/agent-box"}]}}}]}],"stats":{"box1":{"failures":0,"unreachable":0}}}' > "$t/check.json"
set +e; out=$(ba apply); rc=$?; set -e
[[ $rc == 3 && $out == *"would change a limit"* && $(calls) == $((n + 1)) && $(base) == "$c4" ]] && ok "5. a check run that would change a limit path stops before the apply" || bad "5: exit $rc: $out"
echo "$quiet" > "$t/check.json"

# 6
before=$(sha256sum < "$t/box/sudoers.d/agent-box")
cat > "$t/apply-hook" <<EOF
#!/bin/bash
echo 'claude ALL=(root) NOPASSWD: ALL' >> "$t/box/sudoers.d/agent-box"
echo 'claude ALL=(ALL) ALL' > "$t/box/sudoers.d/extra"
chmod 755 "$t/box/keys"
EOF
chmod +x "$t/apply-hook"
set +e; out=$(ba apply); rc=$?; set -e
[[ $rc == 4 && $out == *"changed a limit on the box"* ]] && ok "6a. an apply that changes limit files fails" || bad "6a: exit $rc: $out"
[[ $(sha256sum < "$t/box/sudoers.d/agent-box") == "$before" && ! -e $t/box/sudoers.d/extra && $(stat -c %a "$t/box/keys") == 700 ]] \
  && ok "6b. the changed file, the added file and the folder's mode are put back" || bad "6b: $(ls -l "$t/box/sudoers.d" "$t/box")"
[[ $(base) == "$c4" && -f $t/state/stopped ]] && ok "6c. the baseline stays, and self-applies are stopped" || bad "6c"
rm "$t/apply-hook"
set +e; out=$(ba plan); rc=$?; set -e
[[ $rc == 1 && $out == *"self-applies are stopped"* ]] && ok "6d. the next run refuses until the stop ends" || bad "6d: exit $rc: $out"
rm "$t/state/stopped"   # as a full apply from the controller would

# 7
echo '{"plays":[],"stats":{"box1":{"failures":1,"unreachable":0}}}' > "$t/apply.json"
echo 2 > "$t/rc"
echo '{"plays":[],"stats":{"box1":{"failures":0,"unreachable":0}}}' > "$t/check.json"
echo three > "$t/src/docs/x.md"
commit c6 >/dev/null
set +e; out=$(ba apply); rc=$?; set -e
# The check run also exits 2 here: box-apply accepts 2 from a check run with no failures.
[[ $rc == 1 && $out == *"the apply failed"* && $(base) == "$c4" ]] && ok "7. a failed apply leaves the baseline where it was" || bad "7: exit $rc: $out"

[[ $fail == 0 ]] || exit 1
echo "box-apply: all checks passed"
