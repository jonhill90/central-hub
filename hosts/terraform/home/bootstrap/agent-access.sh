#!/bin/sh
# Bootstrap, run as root on the Proxmox host. Safe to run again.
# It gives agents their own Proxmox user for the dev rebuild VMs only (the owner's yes of
# 2026-11-10 05:16 UTC: "dev pool only", VMs 250-257, nothing on c1, the firewall, 258 or 259):
#   - group agents, role AgentDev (IacOps's list without SDN.Allocate), role AgentClone
#     (clone the AlmaLinux template, nothing else), user agent@pve in agents
#   - pool dev, with any of VMs 250-257 that exist moved in
#   - ACLs for the group and for token agent@pve!dev (privilege-separated)
# The token is made separately so its secret goes straight to a file and is never printed:
#   pveum user token add agent@pve dev --privsep 1 --expire <epoch> --output-format json
# Limit, measured for iac@pve: a new VM is checked on /vms/<id> before it is in its pool, and
# Proxmox drops /vms/<id> ACLs when that VM is destroyed. So the per-ID ACLs below must be
# re-added after each destroy, by running this script again.
# Exit path: `pveum user delete agent@pve; pveum role delete AgentDev; pveum role delete AgentClone;
# pveum group delete agents; pveum pool delete dev` (after the pool is empty).
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
acl /vms/9000 AgentClone 0               # clone the AlmaLinux template; can't change or delete it
acl /sdn/zones/lab/dev AgentDev 0        # attach guests to VNet dev only
acl /storage/local-lvm AgentDev 0        # guest disks
acl /storage/local AgentDev 0            # images the rebuild downloads
acl "/nodes/$NODE" AgentDev 0            # read the node; download-url needs Sys.AccessNetwork here
echo "agent-access: done (node $NODE)"
