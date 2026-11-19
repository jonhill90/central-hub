#!/usr/bin/env bash
# The agent box role's prod_files tasks (hosts/ansible/roles/agent_box/tasks/prod_files.yml) never put an older
# OpenTofu state over the box's own. Runs the task file on localhost, with a stand-in controller home and keys folder:
#   1. The box has no copy: the controller's state is copied.
#   2. The box's copy has the same lineage and a higher serial (a box run changed prod since): the run fails, names
#      the file and both serials, and copies nothing (the box's state and the other prod files are left as they were).
#   3. The box's copy has another lineage: refused the same way.
#   4. The controller's serial is higher, or the same: copied.
#   5. No state content reaches the output, refused or not.
# Usage: .github/hosts-check/tests/test_prod_files_state_age.sh   (needs ansible-core)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

cat > "$t/play.yml" <<PLAY
- hosts: localhost
  gather_facts: false
  tasks:
    - ansible.builtin.include_tasks: $root/hosts/ansible/roles/agent_box/tasks/prod_files.yml
PLAY
state() { # file lineage serial secret
  printf '{"version":4,"terraform_version":"1.9.0","serial":%s,"lineage":"%s","outputs":{"token":{"value":"%s"}},"resources":[]}\n' "$3" "$2" "$4" > "$1"
}
setup() { # fresh controller and box folders; a prod file on the controller
  rm -rf "${t:?}/home" "${t:?}/box" "${t:?}/clone"
  mkdir -p "$t/home/.local/state/central-hub" "$t/home/.config/central-hub" "$t/clone" "$t/box"
  echo "inventory-from-controller" > "$t/home/.config/central-hub/inventory-hosts.yml"
}
run() {
  HOME=$t/home ANSIBLE_LOCALHOST_WARNING=false ANSIBLE_INVENTORY_UNPARSED_WARNING=false \
    ansible-playbook -i localhost, -c local "$t/play.yml" \
    -e "agent_box_keys_dir=$t/box" -e "agent_box_keys_user=$(id -un)" -e "agent_box_prod_files_clone=$t/clone" \
    -e '{"agent_box_prod_files":[{"from":"config","path":"inventory-hosts.yml","dest":"inventory-hosts.yml"}]}' \
    -e "agent_box_prod_theme_src=" -e "ansible_python_interpreter=$(command -v python3)" > "$t/out" 2>&1
  rc=$?; out=$(cat "$t/out")
}
L1=11111111-1111-1111-1111-111111111111 L2=22222222-2222-2222-2222-222222222222
box=$t/box/prod/state/home-k8s.tfstate ctl=$t/home/.local/state/central-hub/home-k8s.tfstate

# 1
setup; state "$ctl" $L1 5 ctl-secret-1; run
if [[ $rc -eq 0 ]] && cmp -s "$ctl" "$box" && [[ -s $t/box/prod/inventory-hosts.yml ]]; then
  ok "1. no copy on the box: the controller's state is copied"
else bad "1. rc=$rc $out"; fi
leak=$out

# 2
setup; mkdir -p "$t/box/prod/state"; state "$box" $L1 9 box-secret-2; state "$ctl" $L1 5 ctl-secret-2; run
if [[ $rc -ne 0 && $out == *"prod files: nothing copied. home-k8s.tfstate: the box is at serial 9 and the controller at 5, so the controller copy is older."* ]] &&
   grep -q box-secret-2 "$box" && [[ ! -e $t/box/prod/inventory-hosts.yml ]]; then
  ok "2. the box's copy is newer (same lineage, higher serial): refused with both serials, nothing copied"
else bad "2. rc=$rc $(grep -c box-secret-2 "$box") $out"; fi
leak+=$out

# 3
setup; mkdir -p "$t/box/prod/state"; state "$box" $L2 1 box-secret-3; state "$ctl" $L1 50 ctl-secret-3; run
if [[ $rc -ne 0 && $out == *"home-k8s.tfstate: the box holds another state (another lineage) than the controller."* ]] &&
   grep -q box-secret-3 "$box"; then
  ok "3. another lineage on the box: refused, the box's state left as it was"
else bad "3. rc=$rc $out"; fi
leak+=$out

# 4
setup; mkdir -p "$t/box/prod/state"; state "$box" $L1 4 box-secret-4; state "$ctl" $L1 7 ctl-secret-4; run; r4a=$rc c4a=$(cmp -s "$ctl" "$box" && echo same)
setup; mkdir -p "$t/box/prod/state"; state "$box" $L1 7 ctl-secret-4b; state "$ctl" $L1 7 ctl-secret-4b; run; r4b=$rc c4b=$(cmp -s "$ctl" "$box" && echo same)
if [[ $r4a -eq 0 && $c4a == same && $r4b -eq 0 && $c4b == same ]]; then
  ok "4. the controller's serial is higher, or the same: copied"
else bad "4. $r4a $c4a $r4b $c4b $out"; fi
leak+=$out

# 5
if [[ $leak != *secret* ]]; then
  ok "5. no state content reaches the output"
else bad "5. state content in the output: $(grep -o '[a-z]*-secret-[0-9a-z]*' <<<"$leak" | sort -u | tr '\n' ' ')"; fi

exit $fail
