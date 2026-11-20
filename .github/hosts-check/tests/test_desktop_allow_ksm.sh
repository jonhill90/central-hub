#!/usr/bin/env bash
# The desktop VM (400) is built out of the host's same-page merging, because the owner types passwords into it (the reviewer's condition
# on playbooks/proxmox-ksm.yml):
#   1. Its tofu creates it stopped (started = false): the provider has no allow-ksm field, so the flag has to be set before its first start.
#   2. `desktop apply` runs tofu apply, then keep_out_of_ksm_and_start, in that order.
#   3. keep_out_of_ksm_and_start sets allow-ksm=0 through the API, then starts the VM; if the API refuses it, the VM stays stopped and
#      the run stops with a message (no start).
# The function is cut from desktop.sh itself, so the test runs the shipped text.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
wrapper=$root/hosts/ansible/roles/agent_box/files/desktop.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0

if grep -qE '^[[:space:]]*started[[:space:]]*=[[:space:]]*false' "$root/hosts/terraform/home/desktop/main.tf" \
   && ! grep -qE '^[[:space:]]*started[[:space:]]*=[[:space:]]*true' "$root/hosts/terraform/home/desktop/main.tf"; then
  ok "1. the desktop's tofu creates the VM stopped"
else bad "1. main.tf does not say started = false"; fi

order=$(awk '/^    apply\)$/ {on=1; next} on && /^    destroy\)$/ {exit} on {print}' "$wrapper" | grep -oE 'tofu apply|keep_out_of_ksm_and_start' | tr '\n' ' ')
if [[ $order == "tofu apply keep_out_of_ksm_and_start " ]]; then ok "2. apply runs tofu apply, then keep_out_of_ksm_and_start"; else bad "2. apply runs: $order"; fi

awk '/^keep_out_of_ksm_and_start\(\) \{$/ {on=1} on {print} on && /^\}$/ {exit}' "$wrapper" > "$t/fn.sh"
[[ -s $t/fn.sh ]] || { echo "FAIL 3. keep_out_of_ksm_and_start was not found in desktop.sh"; exit 1; }
harness() { # <PUT result: ok|fail>
  : > "$t/calls"
  PUT=$1 T=$t bash -c '
    setting() { case $1 in proxmox_node_name) echo pve ;; vm_id) echo 400 ;; esac; }
    px_api() { echo "px_api $*" >> "$T/calls"; [[ $1 != PUT || $PUT == ok ]]; }
    vm_power() { echo "vm_power $*" >> "$T/calls"; }
    . "$T/fn.sh"; keep_out_of_ksm_and_start' > "$t/out" 2>&1 && echo 0 > "$t/rc" || echo $? > "$t/rc"
}
harness ok
if [[ $(tr '\n' '|' < "$t/calls") == "px_api PUT nodes/pve/qemu/400/config allow-ksm=0|vm_power start|" && $(cat "$t/rc") == 0 ]]; then
  ok "3a. allow-ksm=0 is set through the API on VM 400 first, then the VM is started"
else bad "3a. $(tr '\n' '|' < "$t/calls")"; fi
harness fail
if [[ $(tr '\n' '|' < "$t/calls") == "px_api PUT nodes/pve/qemu/400/config allow-ksm=0|" && $(cat "$t/rc") == 1 && $(cat "$t/out") == *"left stopped"* ]]; then
  ok "3b. when the API refuses allow-ksm=0 the VM is not started and the run stops"
else bad "3b. $(tr '\n' '|' < "$t/calls") rc=$(cat "$t/rc")"; fi
exit $fail
