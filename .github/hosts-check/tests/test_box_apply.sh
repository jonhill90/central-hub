#!/usr/bin/env bash
# box-apply (hosts/ansible/roles/agent_box/files/box-apply.py, D-0036), against a local git repository standing in
# for main and a stand-in for ansible-playbook that prints fixed JSON:
#   1. No baseline, a baseline that is not on main, and a wrong argument each refuse.
#   2. A change to free defaults keys and to other files plans and applies, and moves the baseline.
#   3. A change to a limit file, or to a defaults key that is not free, stops before any run.
#   4. A comment-only change in the defaults is not a limit change, and a free key whose value is not a plain
#      literal stops.
#   5. A check run that would change a limit path on the box stops before the apply.
#   6. An apply that changes limit files on the box is put back, never through a link planted at the temporary
#      name, and self-applies stop until the controller ends the stop.
#   7. A failed apply leaves the baseline where it was.
#   8. A limit change with no approval line, a line whose tap is "none", a wrong digest, or a limit change after
#      the line's commit stops and prints the digest to approve; a matching line applies that commit with the
#      limit tasks on and moves the baseline to it, and the next run goes on to main; an approved apply that
#      changes a limit path its check run did not name is put back and stops self-applies; a file the apply adds
#      is named by the loop label (the destination) in the check run, and passes only then; a file copied from a
#      repository file without a loop is named by its source, and passes only with the source's bytes.
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
mkdir -p "$t/box/sudoers.d" "$t/box/libexec" "$t/box/keys" "$t/etc" "$t/state" "$t/bin"
echo 'claude ALL=(keys) NOPASSWD: /x plan' > "$t/box/sudoers.d/agent-box"
chmod 700 "$t/box/keys"
sed -e "s|^SETTINGS = .*|SETTINGS = \"$t/etc/settings.json\"|" -e "s|^LIMITS = .*|LIMITS = \"$t/etc/limits.txt\"|" \
    -e "s|^STATE = .*|STATE = \"$t/state\"|" -e "s|^COPY_DIRS = .*|COPY_DIRS = (\"$t/box/libexec/\",)|" -e "s|^LOG = .*|LOG = \"$t/box-apply.log\"|" -e "s|^LEDGER = .*|LEDGER = \"$t/ledger.jsonl\"|" \
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
box $t/box/libexec/*
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
[[ $out == *"none of them a limit"* ]] && ok "4a. a comment-only change in the defaults is not a limit change" || bad "4a: $out"
n=$(calls)
sed -i "s/^agent_box_tofu_version: .*/agent_box_tofu_version: \"{{ lookup('pipe', 'id') }}\"/" "$t/src/$r/defaults/main.yml"
commit c5b >/dev/null
set +e; out=$(ba plan); rc=$?; set -e
[[ $rc == 3 && $out == *"agent_box_tofu_version (a free key's value must be a plain literal)"* && $(calls) == "$n" ]] \
  && ok "4b. a free key whose new value is Jinja stops before any run" || bad "4b: exit $rc: $out"
sed -i 's/^agent_box_tofu_version: .*/agent_box_tofu_version: "1.13.3"/' "$t/src/$r/defaults/main.yml"
commit c5c >/dev/null
out=$(ba plan) || bad "4c: plan failed: $out"
[[ $out == *"none of them a limit"* ]] && ok "4c. a quoted plain version is free" || bad "4c: $out"

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
ln -s "$t/victim" "$t/box/sudoers.d/agent-box.box-apply"
EOF
echo untouched > "$t/victim"
chmod +x "$t/apply-hook"
set +e; out=$(ba apply); rc=$?; set -e
[[ $rc == 4 && $out == *"changed a limit on the box"* ]] && ok "6a. an apply that changes limit files fails" || bad "6a: exit $rc: $out"
[[ $(sha256sum < "$t/box/sudoers.d/agent-box") == "$before" && ! -e $t/box/sudoers.d/extra && $(stat -c %a "$t/box/keys") == 700 ]] \
  && ok "6b. the changed file, the added file and the folder's mode are put back" || bad "6b: $(ls -l "$t/box/sudoers.d" "$t/box")"
[[ $(cat "$t/victim") == untouched && ! -L $t/box/sudoers.d/agent-box.box-apply && $out != *"agent-box.box-apply ("* ]] \
  && ok "6e. a link planted at the temporary name is taken away, never written through" || bad "6e: $(cat "$t/victim"): $out"
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

# 8
echo 0 > "$t/rc"; echo "$quiet" > "$t/apply.json"; echo "$quiet" > "$t/check.json"
ba apply >/dev/null || bad "8: the plain apply before failed"
appr=hosts/ansible/agent-box-limit-approvals.txt
b8=$(base)
printf -- '- name: z\n  ansible.builtin.debug:\n' >> "$t/src/$r/tasks/main.yml"
l8=$(commit c8)
want=$(git -C "$t/src" diff --no-renames --binary --full-index "$b8" "$l8" -- "$r/tasks/main.yml" | sha256sum | cut -d' ' -f1)
n=$(calls)
set +e; out=$(ba plan); rc=$?; set -e
[[ $rc == 3 && $out == *"no approval line"* && $out == *"$b8 $l8 $want <pass> <tap>"* && $(calls) == "$n" ]] \
  && ok "8a. a limit change with no approval line stops and prints the digest to approve" || bad "8a: exit $rc: $out"
echo "$b8 $l8 $want cmsg_pass01 none" > "$t/src/$appr"
commit c8b >/dev/null
set +e; out=$(ba apply); rc=$?; set -e
[[ $rc == 3 && $out == *"line 1 is malformed"* && $(base) == "$b8" ]] && ok "8b. a line whose tap is none never counts" || bad "8b: exit $rc: $out"
echo "$b8 $l8 $(printf "%064d" 0) cmsg_pass01 card_tap01" > "$t/src/$appr"
commit c8c >/dev/null
set +e; out=$(ba apply); rc=$?; set -e
[[ $rc == 3 && $out == *"its digest is not the diff"* && $(base) == "$b8" ]] && ok "8c. a wrong digest stops" || bad "8c: exit $rc: $out"
echo "$b8 $l8 $want cmsg_pass01 card_tap01" > "$t/src/$appr"
a8=$(commit c8d)
echo '{"plays":[{"tasks":[{"task":{"name":"One sudoers line per wrapper"},"hosts":{"box1":{"changed":true,"diff":[{"before_header":"'"$t"'/box/sudoers.d/agent-box"}]}}}]}],"stats":{"box1":{"failures":0,"unreachable":0}}}' > "$t/check.json"
printf '#!/bin/bash\necho "claude ALL=(keys) NOPASSWD: /x plan, /x apply" > "%s/box/sudoers.d/agent-box"\n' "$t" > "$t/apply-hook"
chmod +x "$t/apply-hook"
: > "$t/calls"
out=$(ba apply) || bad "8d: the approved apply failed: $out"
[[ $out == *"applied the approved limit change ${l8:0:8}"* && $(base) == "$l8" && ! -f $t/state/stopped ]] \
  && grep -q "/x apply" "$t/box/sudoers.d/agent-box" \
  && ok "8d. a matching line applies its commit, keeps the named limit change, and moves the baseline to it" || bad "8d: $out"
[[ $(grep -c -- "-e agent_box_limit_apply=true" "$t/calls") == 2 ]] && tail -n 1 "$t/box-apply.log" | grep -q '"result": "applied-limits"' \
  && tail -n 1 "$t/box-apply.log" | grep -q '"tap": "card_tap01"' \
  && ok "8e. both runs set agent_box_limit_apply, and the log names the line's pass and tap" || bad "8e: $(cat "$t/calls"); $(tail -n 1 "$t/box-apply.log")"
rm "$t/apply-hook"; echo "$quiet" > "$t/check.json"
out=$(ba apply) || bad "8f: the next apply failed: $out"
[[ $out == *"applied ${a8:0:8}"* && $(base) == "$a8" ]] && ok "8f. the next run goes on to main as a plain apply" || bad "8f: $out"
: > "$t/calls"
out=$(ba tick) || bad "8f2: tick failed: $out"
[[ $out == *"nothing new on main since the baseline"* && ! -s $t/calls && $(base) == "$a8" ]] \
  && tail -n 1 "$t/box-apply.log" | grep -q '"result": "nothing-new"' \
  && ok "8f2. the timer's tick with main at the baseline runs no play and logs nothing-new" || bad "8f2: $out; calls: $(cat "$t/calls")"
b9=$(base)
printf -- '- name: w\n  ansible.builtin.debug:\n' >> "$t/src/$r/tasks/main.yml"
l9=$(commit c9)
w9=$(git -C "$t/src" diff --no-renames --binary --full-index "$b9" "$l9" -- "$r/tasks/main.yml" | sha256sum | cut -d' ' -f1)
echo "$b9 $l9 $w9 cmsg_pass02 card_tap02" >> "$t/src/$appr"
printf -- '- name: v\n  ansible.builtin.debug:\n' >> "$t/src/$r/tasks/main.yml"
commit c9b >/dev/null
set +e; out=$(ba plan); rc=$?; set -e
[[ $rc == 0 && $out == *"a limit changed again after ${l9:0:8}; this applies ${l9:0:8} only"* \
  && $out == *"approved limit change"*"to ${l9:0:8}"* && $(base) == "$b9" ]] \
  && ok "8g. a limit change after the line's commit leaves the line good for its own commit only" || bad "8g: exit $rc: $out"
# 8g2: two lines from the baseline, an older one (to l9) and a newer one that reaches further (to lx, which holds l9),
# with a limit change after both: the box applies the newer line, not the first one met.
printf -- '- name: x\n  ansible.builtin.debug:\n' >> "$t/src/$r/tasks/main.yml"
lx=$(commit c9x)
wx=$(git -C "$t/src" diff --no-renames --binary --full-index "$b9" "$lx" -- "$r/tasks/main.yml" | sha256sum | cut -d' ' -f1)
echo "$b9 $lx $wx cmsg_pass02x card_tap02x" >> "$t/src/$appr"
printf -- '- name: z\n  ansible.builtin.debug:\n' >> "$t/src/$r/tasks/main.yml"
commit c9y >/dev/null
set +e; out=$(ba plan); rc=$?; set -e
[[ $rc == 0 && $out == *"a limit changed again after ${lx:0:8}; this applies ${lx:0:8} only"* && $out != *"this applies ${l9:0:8} only"* \
  && $out == *"line "*": ${b9:0:8} to ${lx:0:8}"* && $(base) == "$b9" ]] \
  && ok "8g2. of two lines that both have a later limit change, the one that reaches further is applied" || bad "8g2: exit $rc: $out"
git -C "$t/src" checkout -q "$l9" -- "$r/tasks/main.yml"
commit c9c >/dev/null
echo '{"plays":[{"tasks":[{"task":{"name":"One sudoers line per wrapper"},"hosts":{"box1":{"changed":true,"diff":[{"before_header":"'"$t"'/box/sudoers.d/agent-box"}]}}}]}],"stats":{"box1":{"failures":0,"unreachable":0}}}' > "$t/check.json"
printf '#!/bin/bash\necho "claude ALL=(ALL) ALL" > "%s/box/sudoers.d/extra"\n' "$t" > "$t/apply-hook"
chmod +x "$t/apply-hook"
before=$(sha256sum < "$t/box/sudoers.d/agent-box")
set +e; out=$(ba apply); rc=$?; set -e
[[ $rc == 4 && $out == *"did not name"* && ! -e $t/box/sudoers.d/extra && $(base) == "$b9" && -f $t/state/stopped ]] \
  && ok "8h. an approved apply that changes a limit path its check run did not name is put back and stops" || bad "8h: exit $rc: $out"
rm -f "$t/apply-hook" "$t/state/stopped"

# 8i, 8j: an approved apply that adds a file. A check run gives a file that is not on the box yet no dest, path or
# header, so only the role's loop label (the destination) names it.
printf -- '- name: u\n  ansible.builtin.debug:\n' >> "$t/src/$r/tasks/main.yml"
l10=$(commit c10)
w10=$(git -C "$t/src" diff --no-renames --binary --full-index "$b9" "$l10" -- "$r/tasks/main.yml" | sha256sum | cut -d' ' -f1)
echo "$b9 $l10 $w10 cmsg_pass03 card_tap03" >> "$t/src/$appr"
commit c10b >/dev/null
newf="$t/box/sudoers.d/agent-box-new"
printf '#!/bin/bash\necho "claude ALL=(keys) NOPASSWD: /y plan" > "%s"\n' "$newf" > "$t/apply-hook"
chmod +x "$t/apply-hook"
echo '{"plays":[{"tasks":[{"task":{"name":"Wrappers, root-owned"},"hosts":{"box1":{"changed":true,"results":[{"changed":true,"_ansible_item_label":"new","diff":[{"before":"","after":"x"}]}]}}}]}],"stats":{"box1":{"failures":0,"unreachable":0}}}' > "$t/check.json"
set +e; out=$(ba apply); rc=$?; set -e
[[ $rc == 4 && $out == *"added $newf"* && ! -e $newf && $(base) == "$b9" && -f $t/state/stopped ]] \
  && ok "8i. a new file that the check run did not name by its path is put back and stops" || bad "8i: exit $rc: $out"
rm -f "$t/state/stopped"
echo '{"plays":[{"tasks":[{"task":{"name":"Wrappers, root-owned"},"hosts":{"box1":{"changed":true,"results":[{"changed":true,"_ansible_item_label":"'"$newf"'","diff":[{"before":"","after":"x"}]}]}}}]}],"stats":{"box1":{"failures":0,"unreachable":0}}}' > "$t/check.json"
out=$(ba apply) || bad "8j: the approved apply failed: $out"
[[ $out == *"applied the approved limit change ${l10:0:8}"* && $out == *"$newf"* && -f $newf && $(base) == "$l10" && ! -f $t/state/stopped ]] \
  && ok "8j. the same new file, named by the loop label's destination, passes the guard and moves the baseline" || bad "8j: $out"
# 8k to 8n: a file added by a copy of a repository file to a destination the check run cannot name. For such a result
# the check run's only path is the source in the checkout (after_header), with no dest and no loop label. The apply
# may add a limit file under the box's libexec folder whose bytes equal that source, one file for each such result;
# any other added file is put back: other bytes (8k), a path outside that folder such as sudoers.d (8l), a second
# file for one result (8m). One copy of the source passes (8n).
printf -- '- name: v\n  ansible.builtin.debug:\n' >> "$t/src/$r/tasks/main.yml"
l11=$(commit c11)
w11=$(git -C "$t/src" diff --no-renames --binary --full-index "$l10" "$l11" -- "$r/tasks/main.yml" | sha256sum | cut -d' ' -f1)
echo "$l10 $l11 $w11 cmsg_pass04 card_tap04" >> "$t/src/$appr"
commit c11b >/dev/null
srcf="$t/state/central-hub/$r/tasks/main.yml"
newg="$t/box/libexec/copied.py"; newh="$t/box/libexec/copied2.py"; news="$t/box/sudoers.d/agent-box-copied"
echo '{"plays":[{"tasks":[{"task":{"name":"The helper, root-owned"},"hosts":{"box1":{"changed":true,"diff":[{"before":"","after_header":"'"$srcf"'","after":"x"}]}}}]}],"stats":{"box1":{"failures":0,"unreachable":0}}}' > "$t/check.json"
stops() { # name file... : the apply stops with exit 4 and each file is gone
  local n=$1 f; shift
  set +e; out=$(ba apply); rc=$?; set -e
  for f in "$@"; do [[ ! -e $f ]] || { bad "$n: $f was left"; return; }; done
  [[ $rc == 4 && $out == *"did not name"* && $(base) == "$l10" && -f $t/state/stopped ]] && ok "$n" || bad "$n: exit $rc: $out"
  rm -f "$t/state/stopped"
}
printf '#!/bin/bash\necho "different bytes" > "%s"\n' "$newg" > "$t/apply-hook"
stops "8k. a new file whose bytes are not those of the source the check run named is put back and stops" "$newg"
printf '#!/bin/bash\ncp "%s" "%s"\n' "$srcf" "$news" > "$t/apply-hook"
stops "8l. a copy of the named source under sudoers.d is put back and stops" "$news"
printf '#!/bin/bash\ncp "%s" "%s"\ncp "%s" "%s"\n' "$srcf" "$newg" "$srcf" "$newh" > "$t/apply-hook"
stops "8m. two copies of one named source, from one result, are put back and stop" "$newg" "$newh"
printf '#!/bin/bash\ncp "%s" "%s"\n' "$srcf" "$newg" > "$t/apply-hook"
out=$(ba apply) || bad "8n: the approved apply failed: $out"
[[ $out == *"applied the approved limit change ${l11:0:8}"* && $out == *"$newg"* && -f $newg && $(base) == "$l11" && ! -f $t/state/stopped ]] \
  && ok "8n. one copy of the named source under the libexec folder, with no dest or label, passes the guard" || bad "8n: $out"
rm -f "$t/apply-hook"

# 9: the reviewer's recorded digest pass replaces the approval line (the owner's order of 2026-11-22). The ledger holds one
# JSON line per pass (pass-record digest-pass). Only recorder "reviewer" or "orchestrator" counts, from and digest must match, and the pass
# and tap are ids; the standing tap is the box's own constant.
b12=$(base)
printf -- '- name: w\n  ansible.builtin.debug:\n' >> "$t/src/$r/tasks/main.yml"
l12=$(commit c12)
w12=$(git -C "$t/src" diff --no-renames --binary --full-index "$b12" "$l12" -- "$r/tasks/main.yml" | sha256sum | cut -d' ' -f1)
echo 0 > "$t/rc"; echo "$quiet" > "$t/apply.json"; echo "$quiet" > "$t/check.json"
set +e; out=$(ba apply); rc=$?; set -e
[[ $rc == 3 && $out == *"pass-record digest-pass $b12 $l12 $w12"* && $(base) == "$b12" ]] \
  && ok "9a. with no line and no ledger entry the stop names the digest-pass command" || bad "9a: exit $rc: $out"
printf '%s\n' '{"from":"'"$b12"'","to":"'"$l12"'","digest":"'"$w12"'","relay_ref":"cmsg_pass12","recorder":"builder"}' > "$t/ledger.jsonl"
set +e; out=$(ba apply); rc=$?; set -e
[[ $rc == 3 && $(base) == "$b12" ]] && ok "9b. a digest pass recorded by a builder never counts" || bad "9b: exit $rc: $out"
printf '%s\n' '{"from":"'"$b12"'","to":"'"$l12"'","digest":"'"$(printf "%064d" 0)"'","relay_ref":"cmsg_pass12","recorder":"reviewer"}' > "$t/ledger.jsonl"
set +e; out=$(ba apply); rc=$?; set -e
[[ $rc == 3 && $out == *"its digest is not the diff"* && $(base) == "$b12" ]] && ok "9c. a digest pass with a wrong digest stops" || bad "9c: exit $rc: $out"
printf '%s\n' 'not json' '{"from":"'"$b12"'","to":"'"$l12"'","digest":"'"$w12"'","relay_ref":"cmsg_pass12","recorder":"orchestrator"}' > "$t/ledger.jsonl"
out=$(ba apply) || bad "9d: the apply on the reviewer's digest pass failed: $out"
[[ $out == *"applied the approved limit change ${l12:0:8}"* && $(base) == "$l12" && ! -f $t/state/stopped ]] \
  && tail -n 1 "$t/box-apply.log" | grep -q '"pass": "cmsg_pass12"' \
  && tail -n 1 "$t/box-apply.log" | grep -q '"tap": "cmsg_01X43rfNYp4H1dL1V2dkfkwN9ubbtsV3Wpcx228ZrApLVh"' \
  && ok "9d. the reviewer's recorded digest pass applies its commit with no approval line, and the log names the pass and the standing tap" || bad "9d: $out"

[[ $fail == 0 ]] || exit 1
echo "box-apply: all checks passed"
