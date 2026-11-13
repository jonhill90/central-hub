#!/bin/sh
# Bootstrap, run as root on the Proxmox host. Safe to run again.
# It gives agents their own Proxmox user for the dev rebuild VMs only (the owner's yes of
# 2026-11-10 05:16 UTC: "dev pool only", VMs 250-257, nothing on c1, the firewall, 258 or 259),
# and the notebook's CI runner, VM 300 in pool ci (the owner's go of 2026-11-10 20:05 UTC to move the
# notebook's CI off GitHub-hosted minutes; the VM and its ID are agent picks, docs/runbooks/set-up-the-ci-runner.md):
#   - group agents, role AgentDev (IacOps's list without SDN.Allocate), role AgentClone
#     (clone the agents' template, nothing else), user agent@pve in agents
#   - template 9001: a copy of template 9000 with its network on VNet dev, for the agents to clone
#   - pool dev, with any of VMs 250-257 that exist moved in; pool ci, with VM 300 if it exists
#   - ACLs for the group and for token agent@pve!dev (privilege-separated)
# The token is made separately so its secret goes straight to a file and is never printed:
#   pveum user token add agent@pve dev --privsep 1 --expire <epoch> --output-format json
# Limit, measured for iac@pve: a new VM is checked on /vms/<id> before it is in its pool, and
# Proxmox drops /vms/<id> ACLs when that VM is destroyed. So the per-ID ACLs below must be
# re-added after each destroy, by running this script again.
# Exit path: `pveum user delete agent@pve; pveum role delete AgentDev; pveum role delete AgentClone;
# pveum group delete agents; pveum pool delete dev; pveum pool delete ci; qm destroy 9001` (after the pools are empty).
set -eu

NODE=$(hostname)
PRIVS="Datastore.Audit,Datastore.AllocateSpace,Datastore.AllocateTemplate,Pool.Audit,SDN.Audit,SDN.Use,Sys.Audit,VM.Audit,VM.Allocate,VM.Clone,VM.Config.Cloudinit,VM.Config.CDROM,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.PowerMgmt,VM.GuestAgent.Audit,Sys.AccessNetwork"
CLONE_PRIVS="VM.Audit,VM.Clone"

pveum group list --output-format json | grep -q '"groupid":"agents"' || pveum group add agents --comment "Agents' own access: dev rebuild VMs only"
for r in "AgentDev:$PRIVS" "AgentClone:$CLONE_PRIVS"; do
  role=${r%%:*}; privs=${r#*:}
  if pveum role list --output-format json | grep -q "\"roleid\":\"$role\""; then
    pveum role modify "$role" --privs "$privs"
  else
    pveum role add "$role" --privs "$privs"
  fi
done
pveum user list --output-format json | grep -q '"userid":"agent@pve"' || pveum user add agent@pve --groups agents --comment "Agents: dev rebuilds (VMs 250-257)"

pveum pool list --output-format json | grep -q '"poolid":"dev"' || pveum pool add dev --comment "Dev rebuild VMs 250-257"
for id in 250 251 252 253 254 255 256 257; do
  qm status "$id" >/dev/null 2>&1 || continue
  pvesh get /pools/dev --output-format json | grep -q "\"vmid\":$id" || pvesh set /pools/dev --vms "$id" --allow-move 1
done
pveum pool list --output-format json | grep -q '"poolid":"ci"' || pveum pool add ci --comment "The notebook's CI runner, VM 300"
if qm status 300 >/dev/null 2>&1; then
  pvesh get /pools/ci --output-format json | grep -q '"vmid":300' || pvesh set /pools/ci --vms 300 --allow-move 1
fi

# Template 9001, the agents' copy of template 9000 on VNet dev. Proxmox checks SDN.Use on the
# source's network when it clones: agent@pve!dev cloning 9000 (on VNet prod) got 403 "Permission
# check failed (/sdn/zones/lab/prod, SDN.Use)", measured 2026-11-10. The agents get no use of prod,
# so they clone this copy. It is made once: after template 9000 is rebuilt, run
# `qm destroy 9001` and then this script again.
if ! qm status 9001 >/dev/null 2>&1; then
  qm clone 9000 9001 --name almalinux10-dev-template --full 1
  qm set 9001 --net0 virtio,bridge=dev
  qm template 9001
fi

# One ACL line per path: <path> <role> <propagate>
acl() {
  for who in "--groups agents" "--tokens agent@pve!dev"; do
    case "$who" in
      --tokens*) pveum user token list agent@pve --output-format json | grep -q '"tokenid":"dev"' || continue ;;
    esac
    # shellcheck disable=SC2086
    pveum acl modify "$1" $who --roles "$2" --propagate "$3"
  done
}
acl /pool/dev AgentDev 1
for id in 250 251 252 253 254 255 256 257; do acl "/vms/$id" AgentDev 0; done
acl /pool/ci AgentDev 1
acl /vms/300 AgentDev 0                  # the CI runner
acl /vms/9001 AgentClone 0               # clone the agents' template; can't change or delete it
acl /sdn/zones/lab/dev AgentDev 0        # attach guests to VNet dev only
acl /storage/local-lvm AgentDev 0        # guest disks
acl /storage/local AgentDev 0            # images the rebuild downloads
acl "/nodes/$NODE" AgentDev 0            # read the node; download-url needs Sys.AccessNetwork here
# Template 9000 is on VNet prod, which the agents may not use, so they no longer need it.
pveum acl delete /vms/9000 --groups agents --roles AgentClone 2>/dev/null || true
pveum acl delete /vms/9000 --tokens 'agent@pve!dev' --roles AgentClone 2>/dev/null || true

# ===== Part 2: the agents' lab account, agentlab@pve (was agent-lab-access.sh; one file because the
# Mac wrapper sends only this one over ssh) =====
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

BOX_VNET=dev                         # VM 258's VNet (STD-0001, hosts/terraform/home/jumpbox)
NO_ACCESS="258 259"                  # the agent box and CT 259: never touched by agents
READ_ONLY="900"                      # the tailnet connector: only root@pam can make it again
LAB_PRIVS="Datastore.Audit,Datastore.AllocateSpace,Datastore.AllocateTemplate,Pool.Audit,SDN.Audit,SDN.Use,SDN.Allocate,Sys.Audit,VM.Audit,VM.Allocate,VM.Clone,VM.Config.Cloudinit,VM.Config.CDROM,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.PowerMgmt,VM.GuestAgent.Audit,Sys.AccessNetwork"

pveum group list --output-format json | grep -q '"groupid":"agents-lab"' || pveum group add agents-lab --comment "Agents' lab rebuilds: every guest but 258 and 259"
for r in "AgentLab:$LAB_PRIVS" "AgentLabUse:SDN.Audit,SDN.Use" "AgentLabAudit:VM.Audit" "AgentLabPools:Pool.Audit"; do
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
lab_acl() {
  for who in "--groups agents-lab" "--tokens agentlab@pve!lab"; do
    case "$who" in
      --tokens*) token_exists || continue ;;
    esac
    # shellcheck disable=SC2086
    pveum acl modify "$1" $who --roles "$2" --propagate "$3"
  done
}
# The limits first, so there is no moment where /vms reaches them.
for id in $NO_ACCESS; do lab_acl "/vms/$id" NoAccess 0; done
for id in $READ_ONLY; do lab_acl "/vms/$id" AgentLabAudit 0; done
lab_acl "/sdn/zones/lab/$BOX_VNET" AgentLabUse 1
lab_acl /vms AgentLab 1                      # every other guest, and templates 9000 and 9001
lab_acl /pool AgentLabPools 1                # see pool members; a pool role never beats NoAccess
lab_acl /sdn AgentLab 0                      # the SDN applier (PUT /cluster/sdn)
lab_acl /sdn/zones/lab AgentLab 1            # zone lab's other VNets and their subnets
lab_acl /sdn/zones/localnetwork/vmbr0 AgentLab 0   # the firewall's WAN NIC
lab_acl /sdn/zones/localnetwork/vmbr1 AgentLab 0   # the firewall's trunk NIC
lab_acl /storage/local-lvm AgentLab 0        # guest disks
lab_acl /storage/local AgentLab 0            # images and the container template
lab_acl "/nodes/$NODE" AgentLab 0            # read the node; download-url needs Sys.AccessNetwork here

# Check the limits as Proxmox computes them, for the token if it exists, else for the user.
lab_check() {
  if token_exists; then
    out=$(pveum user token permissions agentlab@pve lab --path "$1" --output-format json)
  else
    out=$(pveum user permissions agentlab@pve --path "$1" --output-format json)
  fi
  if printf '%s' "$out" | grep -Eq "$2"; then
    echo "agent-access: STOP, $1 still allows $2: $out" >&2
    exit 1
  fi
}
for id in $NO_ACCESS; do lab_check "/vms/$id" '"(VM|SDN|Datastore|Sys)\.'; done
for id in $READ_ONLY; do lab_check "/vms/$id" '"VM\.(Allocate|PowerMgmt|Config)'; done
lab_check "/sdn/zones/lab/$BOX_VNET" '"SDN\.Allocate'
echo "agent-access: done (node $NODE)"
