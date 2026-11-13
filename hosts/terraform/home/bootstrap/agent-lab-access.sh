#!/bin/sh
# Bootstrap, run as root on the Proxmox host. Safe to run again.
# It gives agents a second Proxmox user for rebuilding the whole lab from the agent box (the owner's
# pick "Everything on Proxmox" of 2026-11-13 05:08 UTC: every guest except VM 258 and CT 259, not
# the host install). The limits are the token's own rights, not only the wrapper's code:
#   - group agents-lab, role AgentLab (IacOps's list), role AgentLabUse (SDN.Audit, SDN.Use),
#     role AgentLabAudit (VM.Audit), role AgentLabPools (Pool.Audit), user agentlab@pve in agents-lab
#   - ACLs for the group and for token agentlab@pve!lab (privilege-separated):
#     AgentLab on /vms, propagated, so every guest ID, one that exists today or one made later;
#     NoAccess on /vms/258 (the agent box) and /vms/259; AgentLabAudit on /vms/900; AgentLabPools on
#     /pool, so OpenTofu can read which pool a guest is in. Without it, GET /pools lists no pool
#     (PVE source: API2/Pool.pm), bpg reads pool_id as empty and plans a pool change, which needs
#     Pool.Allocate, which the token doesn't get (it can't move a guest, 258 included, into a pool).
# A deeper ACL replaces the roles a path inherits, and NoAccess is never trumped by a pool's roles
# (PVE source: AccessControl.pm `roles`, RPCEnvironment.pm `compile_acl_path`). Proxmox drops a
# VM's ACLs only when that VM is destroyed, and the token can't destroy 258, 259 or 900.
# CT 900 (the tailnet connector) gets read only: its config has keyctl and /dev/net/tun, which only
# root@pam may set (PVE source: LXC.pm `check_ct_modify_config_perm`), so no token can make it
# again, and a token that could destroy it would cut remote access with no way back.
# The box's own VNet (dev) gets SDN.Use only: an agent may rebuild the other VNets but may not
# change or delete the VNet dev object itself. Zone lab's own settings stay editable (AgentLab on
# /sdn/zones/lab); the zone can't be deleted while a VNet uses it (PVE source: Zones/Plugin.pm).
# The token is made separately so its secret goes straight to a file and is never printed:
#   pveum user token add agentlab@pve lab --privsep 1 --expire <epoch> --output-format json
# Exit path: `pveum user delete agentlab@pve; pveum role delete AgentLab; pveum role delete
# AgentLabUse; pveum role delete AgentLabAudit; pveum role delete AgentLabPools;
# pveum group delete agents-lab` (the ACLs go with them).
set -eu

NODE=$(hostname)
BOX_VNET=dev                         # VM 258's VNet (STD-0001, hosts/terraform/home/jumpbox)
NO_ACCESS="258 259"                  # the agent box and CT 259: never touched by agents
READ_ONLY="900"                      # the tailnet connector: only root@pam can make it again
PRIVS="Datastore.Audit,Datastore.AllocateSpace,Datastore.AllocateTemplate,Pool.Audit,SDN.Audit,SDN.Use,SDN.Allocate,Sys.Audit,VM.Audit,VM.Allocate,VM.Clone,VM.Config.Cloudinit,VM.Config.CDROM,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.PowerMgmt,VM.GuestAgent.Audit,Sys.AccessNetwork"

pveum group list --output-format json | grep -q '"groupid":"agents-lab"' || pveum group add agents-lab --comment "Agents' lab rebuilds: every guest but 258 and 259"
for r in "AgentLab:$PRIVS" "AgentLabUse:SDN.Audit,SDN.Use" "AgentLabAudit:VM.Audit" "AgentLabPools:Pool.Audit"; do
  role=${r%%:*}; privs=${r#*:}
  if pveum role list --output-format json | grep -q "\"roleid\":\"$role\""; then
    pveum role modify "$role" --privs "$privs"
  else
    pveum role add "$role" --privs "$privs"
  fi
done
pveum user list --output-format json | grep -q '"userid":"agentlab@pve"' || pveum user add agentlab@pve --groups agents-lab --comment "Agents: lab rebuilds from the agent box"

token_exists() { pveum user token list agentlab@pve --output-format json | grep -q '"tokenid":"lab"'; }

# One ACL line per path: <path> <role> <propagate>
acl() {
  for who in "--groups agents-lab" "--tokens agentlab@pve!lab"; do
    case "$who" in
      --tokens*) token_exists || continue ;;
    esac
    # shellcheck disable=SC2086
    pveum acl modify "$1" $who --roles "$2" --propagate "$3"
  done
}
# The limits first, so there is no moment where /vms reaches them.
for id in $NO_ACCESS; do acl "/vms/$id" NoAccess 0; done
for id in $READ_ONLY; do acl "/vms/$id" AgentLabAudit 0; done
acl "/sdn/zones/lab/$BOX_VNET" AgentLabUse 1
acl /vms AgentLab 1                      # every other guest, and templates 9000 and 9001
acl /pool AgentLabPools 1                # see pool members; a pool role never beats NoAccess
acl /sdn AgentLab 0                      # the SDN applier (PUT /cluster/sdn)
acl /sdn/zones/lab AgentLab 1            # zone lab's other VNets and their subnets
acl /sdn/zones/localnetwork/vmbr0 AgentLab 0   # the firewall's WAN NIC
acl /sdn/zones/localnetwork/vmbr1 AgentLab 0   # the firewall's trunk NIC
acl /storage/local-lvm AgentLab 0        # guest disks
acl /storage/local AgentLab 0            # images and the container template
acl "/nodes/$NODE" AgentLab 0            # read the node; download-url needs Sys.AccessNetwork here

# Check the limits as Proxmox computes them, for the token if it exists, else for the user.
check() {
  if token_exists; then
    out=$(pveum user token permissions agentlab@pve lab --path "$1" --output-format json)
  else
    out=$(pveum user permissions agentlab@pve --path "$1" --output-format json)
  fi
  if printf '%s' "$out" | grep -Eq "$2"; then
    echo "agent-lab-access: STOP, $1 still allows $2: $out" >&2
    exit 1
  fi
}
for id in $NO_ACCESS; do check "/vms/$id" '"(VM|SDN|Datastore|Sys)\.'; done
for id in $READ_ONLY; do check "/vms/$id" '"VM\.(Allocate|PowerMgmt|Config)'; done
check "/sdn/zones/lab/$BOX_VNET" '"SDN\.Allocate'
echo "agent-lab-access: done (node $NODE)"
