#!/bin/bash
# /usr/local/libexec/agent-box/dev-vms.sh: plan, apply or destroy the dev rebuild VMs (250-257)
# with the agents' own Proxmox token. It runs as user `keys` through sudo, so the session that
# asks for it never sees the token (docs/runbooks/set-up-the-agent-box.md). Installed by the
# agent_box role; root owns it, so a session can't change what it runs.
#   sudo -n -u keys /usr/local/libexec/agent-box/dev-vms.sh plan|apply|destroy
set -euo pipefail
umask 077

case ${1:-} in
  plan | apply | destroy) action=$1 ;;
  *) echo "usage: dev-vms plan|apply|destroy" >&2; exit 2 ;;
esac

keys=/etc/agent-keys
work=/var/lib/agent-box
repo=$work/checkouts/dev-vms   # this wrapper's own checkout of central-hub
folder=$repo/hosts/terraform/home/k8s
state=$work/state/dev-vms.tfstate
plan=$work/state/dev-vms.tfplan
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin TF_DATA_DIR=$work/tofu-data/dev-vms TF_IN_AUTOMATION=1

# Only reviewed code on main runs with the token, never a checkout a session can edit.
# One dev-vms run at a time, in its own checkout: no other run, of this wrapper or another, can
# move the code under it. The lock is held until the run and everything it starts end.
exec 9>"$work/state/dev-vms.lock"
flock -n 9 || { echo "dev-vms: another dev-vms run is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
echo "dev-vms: central-hub $(git -C "$repo" rev-parse --short HEAD)"

# PROXMOX_VE_ENDPOINT and PROXMOX_VE_API_TOKEN (agent@pve!dev), plus PROXMOX_VE_INSECURE if needed.
set -a
# shellcheck source=/dev/null
. "$keys/proxmox-dev.env"
set +a

tofu() { /usr/local/bin/tofu -chdir="$folder" "$@"; }
# The VLAN file from this run's own checkout, over any path the tfvars give. Pool dev and template
# 9001 as rebuild.sh sets them, since both wrappers share one state: the token clones only 9001, and
# a pool other than dev would plan a pool move, which needs Pool.Allocate the token doesn't have.
vlans=(-var "vlans_file=$repo/hosts/ansible/inventories/home/group_vars/all/vlans.yml" -var "pool_id=dev" -var "template_vm_id=9001")
tofu init -input=false -backend-config="path=$state" >/dev/null

case $action in
  plan) tofu plan -input=false -var-file="$keys/dev-vms.tfvars" "${vlans[@]}" -out="$plan" ;;
  apply)
    [[ -f $plan ]] || { echo "dev-vms: no saved plan; run dev-vms plan first" >&2; exit 1; }
    tofu apply -input=false "$plan"
    rm -f "$plan"
    ;;
  destroy)
    tofu plan -destroy -input=false -var-file="$keys/dev-vms.tfvars" "${vlans[@]}" -out="$plan"
    tofu apply -input=false "$plan"
    rm -f "$plan"
    ;;
esac
