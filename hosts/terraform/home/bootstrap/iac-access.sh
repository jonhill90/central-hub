#!/bin/sh
# Bootstrap, run once as root on the Proxmox host, before the first tofu run. Safe to run again.
# It creates what Terraform needs in order to log in, plus the pools Terraform puts machines in:
#   - group iac, role IacOps (least privilege for hosts/terraform/home/*), user iac@pve in iac
#   - pools firewall and remote-access, with VM 100 and CT 900 moved into them
#   - ACLs for the group and for token iac@pve!apply (privilege-separated, so the token needs its own)
# The token itself is made separately, because its secret must go straight to a file and never be
# printed (see hosts/RUNLOG-2026-10-26.md, step 2):
#   pveum user token add iac@pve apply --privsep 1 --expire <epoch> --output-format json
# Privilege list: from the bpg/proxmox v0.116.0 docs example (docs/index.md L181), cut down to
# the resources this draft manages; names are PVE 9 names (checked with `pveum role list`).
# Exit path: `pveum user delete iac@pve; pveum role delete IacOps; pveum group delete iac`.
set -eu

NODE=$(hostname)
PRIVS="Datastore.Audit,Datastore.AllocateSpace,Pool.Audit,SDN.Audit,SDN.Use,SDN.Allocate,Sys.Audit,VM.Audit,VM.Allocate,VM.Config.CDROM,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.PowerMgmt,VM.GuestAgent.Audit"

pveum group list --output-format json | grep -q '"groupid":"iac"' || pveum group add iac --comment "Infrastructure as code (Terraform/OpenTofu)"
if pveum role list --output-format json | grep -q '"roleid":"IacOps"'; then
  pveum role modify IacOps --privs "$PRIVS"
else
  pveum role add IacOps --privs "$PRIVS"
fi
pveum user list --output-format json | grep -q '"userid":"iac@pve"' || pveum user add iac@pve --groups iac --comment "Terraform/OpenTofu runs from hosts/terraform"

for pool in firewall remote-access; do
  pveum pool list --output-format json | grep -q "\"poolid\":\"$pool\"" || pveum pool add "$pool" --comment "Workload $pool (hosts/terraform/home/$pool)"
done
# Move each machine into its workload's pool (a guest belongs to at most one pool).
pvesh get /pools/firewall --output-format json | grep -q '"vmid":100' || pvesh set /pools/firewall --vms 100 --allow-move 1
pvesh get /pools/remote-access --output-format json | grep -q '"vmid":900' || pvesh set /pools/remote-access --vms 900 --allow-move 1

# One ACL line per path: <path> <propagate>
acl() {
  for who in "--groups iac" "--tokens iac@pve!apply"; do
    case "$who" in
      --tokens*) pveum user token list iac@pve --output-format json | grep -q '"tokenid":"apply"' || continue ;;
    esac
    # shellcheck disable=SC2086
    pveum acl modify "$1" $who --roles IacOps --propagate "$2"
  done
}
acl /sdn 0                               # the SDN applier (PUT /cluster/sdn)
acl /sdn/zones/lab 1                     # zone lab, its VNets and subnets
acl /sdn/zones/localnetwork/vmbr0 0      # attach the WAN NIC and the connector's eth0
acl /sdn/zones/localnetwork/vmbr1 0      # attach the firewall's trunk NIC
acl /pool/firewall 1                     # VM 100
acl /pool/remote-access 1                # CT 900
acl /storage/local-lvm 0                 # guest disks
acl /storage/local 0                     # the container template
acl "/nodes/$NODE" 0                     # read the node and its networks
echo "iac-access: done (node $NODE)"
