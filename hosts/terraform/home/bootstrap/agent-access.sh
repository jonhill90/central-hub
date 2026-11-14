#!/bin/sh
# Bootstrap, run as root on the Proxmox host. Safe to run again.
# The desktop rights are a committed value, not an argument: DESKTOP_ACCESS below is on or off, and
# every run gives AgentDev on /pool/desktop when it is on and takes it away when it is off. It stays
# off except while one `desktop apply` or `destroy` runs (the owner's pick 219, 2026-11-14 02:18 UTC:
# "No rights after build"; a token can't remove its own ACL, so the toggle is a reviewed PR plus a
# run of this script, never the agents' own step).
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
# The dev VMs get their rights from pool dev, not from /vms/<id> ACLs, which Proxmox drops when a
# VM is destroyed. A clone that names pool dev needs VM.Allocate on /pool/dev only, and Proxmox adds
# the clone to the pool before the clone task ends, so the provider's next call (tags, CPU, disks)
# already finds the VM in the pool (qemu-server API2/Qemu.pm clone_vm: the permission check and
# add_vm_to_pool). The pool's roles reach /vms/<id> of each member (pve-access-control
# RPCEnvironment.pm compile_acl_path). This holds for clones only: a create that sets tags is
# checked on /vms/<id> before the VM is in its pool (pick 18), and the dev rebuild only clones 9001.
# Exit path: `pveum user delete agent@pve; pveum role delete AgentDev; pveum role delete AgentClone;
# pveum group delete agents; pveum pool delete dev; pveum pool delete ci; pveum pool delete desktop; qm destroy 9001` (after the pools are empty).
set -eu

# on or off. Off is the default; a PR sets it to on for one desktop apply or destroy and back to off after.
DESKTOP_ACCESS=off
case $DESKTOP_ACCESS in on | off) ;; *) echo "agent-access: DESKTOP_ACCESS must be on or off" >&2; exit 2 ;; esac
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
pveum pool list --output-format json | grep -q '"poolid":"desktop"' || pveum pool add desktop --comment "The owner's desktop VM, ID 400-499"
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
acl /pool/dev AgentDev 1                 # VMs 250-257, made again after every teardown
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
# The owner's desktop (400-499): rights only while DESKTOP_ACCESS is on, so the agents keep none on a
# VM where the owner types passwords.
if [ "$DESKTOP_ACCESS" = on ]; then
  acl /pool/desktop AgentDev 1
else
  pveum acl delete /pool/desktop --groups agents --roles AgentDev 2>/dev/null || true
  pveum acl delete /pool/desktop --tokens 'agent@pve!dev' --roles AgentDev 2>/dev/null || true
fi
echo "agent-access: done (node $NODE, desktop access $DESKTOP_ACCESS)"
