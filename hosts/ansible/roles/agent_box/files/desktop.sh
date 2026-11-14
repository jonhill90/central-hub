#!/bin/bash
# /usr/local/libexec/agent-box/desktop.sh: build and set up the owner's desktop VM
# (docs/runbooks/set-up-the-desktop.md). It runs as user `keys` through sudo, so the session that
# asks for it never sees the Proxmox token or the VM's SSH key. Installed by the agent_box role;
# root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/desktop.sh plan|apply|configure|destroy
# plan, apply, destroy: OpenTofu on hosts/terraform/home/desktop with the agents' Proxmox token.
# configure: the desktop playbook over SSH as the cloud-init admin user. The role removes that
# user's key at the end of its run, so a second configure on the same VM can't log in: a change is a
# destroy and a rebuild. The owner's password is never handled here: the owner types it at the
# Proxmox console, so it passes through no agent, file or log.
set -euo pipefail
umask 077

case ${1:-} in
  plan | apply | configure | destroy) action=$1 ;;
  *) echo "usage: desktop plan|apply|configure|destroy" >&2; exit 2 ;;
esac

keys=/etc/agent-keys
work=/var/lib/agent-box
repo=$work/checkouts/desktop   # this wrapper's own checkout of central-hub
folder=$repo/hosts/terraform/home/desktop
settings=$work/desktop.json   # private values the agent_box role writes from the inventory
state=$work/state/desktop.tfstate
plan=$work/state/desktop.tfplan
vars=$work/state/desktop.tfvars.json
sshkey=$keys/desktop-ssh
# Ansible comes from the box's own virtual environment (role agent_box), as in the rebuild wrapper.
export HOME=$work PATH=/usr/local/libexec/agent-box/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin
export TF_DATA_DIR=$work/tofu-data/desktop TF_IN_AUTOMATION=1 ANSIBLE_COLLECTIONS_PATH=/usr/local/libexec/agent-box/collections ANSIBLE_HOME=$work/ansible-home

[[ -f $settings ]] || { echo "desktop: $settings is missing; set agent_box_desktop in the inventory and run the agent_box role" >&2; exit 1; }

# Only reviewed code on main runs with the keys, never a checkout a session can edit.
# One desktop run at a time, in its own checkout: no other run, of this wrapper or another, can
# move the code under it. The lock is held until the run and everything it starts end.
exec 9>"$work/state/desktop.lock"
flock -n 9 || { echo "desktop: another desktop run is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
echo "desktop: central-hub $(git -C "$repo" rev-parse --short HEAD)"

# The VM's own SSH key, made here the first time. Only its public half leaves this folder.
[[ -f $sshkey ]] || ssh-keygen -q -t ed25519 -N "" -C "keys@agent-box desktop" -f "$sshkey"

tofu_run() {
  python3 -I - "$settings" "$sshkey.pub" "$repo" "$vars" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
json.dump({
    "proxmox_node_name": s["proxmox_node_name"],
    "vnet": s["vnet"],
    "vlans_file": sys.argv[3] + "/hosts/ansible/inventories/home/group_vars/all/vlans.yml",
    "template_vm_id": s["template_vm_id"],
    "ssh_public_key": open(sys.argv[2]).read().strip(),
    "desktop": {k: s[k] for k in ("name", "vm_id", "address", "cores", "memory_mb", "disk_gb")},
}, open(sys.argv[4], "w"))
PY
  # PROXMOX_VE_ENDPOINT and PROXMOX_VE_API_TOKEN (agent@pve!dev).
  set -a
  # shellcheck source=/dev/null
  . "$keys/proxmox-dev.env"
  set +a
  tofu() { /usr/local/bin/tofu -chdir="$folder" "$@"; }
  tofu init -input=false -backend-config="path=$state" >/dev/null
  case $action in
    plan) tofu plan -input=false -var-file="$vars" -out="$plan" ;;
    apply)
      [[ -f $plan ]] || { echo "desktop: no saved plan; run desktop plan first" >&2; exit 1; }
      tofu apply -input=false "$plan"
      rm -f "$plan"
      ;;
    destroy)
      tofu plan -destroy -input=false -var-file="$vars" -out="$plan"
      tofu apply -input=false "$plan"
      rm -f "$plan"
      ;;
  esac
}

configure() {
  local extra inventory
  extra=$(mktemp --suffix=.json "$work/state/desktop-extra.XXXXXX")
  # The .json suffix makes Ansible read the inventory as YAML (JSON), not INI.
  inventory=$(mktemp --suffix=.json "$work/state/desktop-inventory.XXXXXX")
  # Expanded now: the trap runs after configure returns, when its locals are gone.
  # shellcheck disable=SC2064
  trap "rm -f '$extra' '$inventory'" EXIT
  python3 -I - "$settings" "$inventory" "$extra" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
admin = s.get("admin_user", "admin")
json.dump({"desktop": {"hosts": {"desktop_vm": {
    "ansible_host": s["address"], "ansible_user": admin}}}}, open(sys.argv[2], "w"))
json.dump({"desktop_rdp_source": s["rdp_source"], "desktop_admin_user": admin}, open(sys.argv[3], "w"))
PY
  mkdir -p "$work/.ssh"
  cd "$repo/hosts/ansible"
  # A rebuilt VM has a new host key, and the run stops on it: remove its line from
  # $work/.ssh/known_hosts after checking (docs/runbooks/set-up-the-desktop.md).
  ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$work/.ssh/known_hosts" \
    ansible-playbook -i "$inventory" --private-key "$sshkey" -e "@$extra" playbooks/desktop.yml
}

case $action in
  configure) configure ;;
  *) tofu_run ;;
esac
