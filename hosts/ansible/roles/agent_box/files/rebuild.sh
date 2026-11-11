#!/bin/bash
# /usr/local/libexec/agent-box/rebuild.sh: run the one-command rebuild of the DEV Kubernetes layer
# (hosts/rebuild-k8s.sh, docs/runbooks/rebuild-k8s-layer-with-one-command.md) from the agent box.
# It runs as user `keys` through sudo, so the session that asks for it never sees the Proxmox
# token, the node SSH key or the dev inventory. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/rebuild.sh up|rebuild|teardown
# up: all stages. rebuild: tear the dev VMs down first, then all stages. teardown: only the teardown.
# Dev only: the env file below fixes ENV_NAME=dev and the dev VM range 250-257, and rebuild-k8s.sh
# refuses a tfvars whose VM IDs fall outside it or whose node_vnet isn't "dev". Only code on main
# runs with the keys; there is no way to name another branch.
set -euo pipefail
umask 077

case ${1:-} in
  up) extra=() ;;
  rebuild) extra=(--teardown) ;;
  teardown) extra=(--only teardown) ;;
  *) echo "usage: rebuild up|rebuild|teardown" >&2; exit 2 ;;
esac

keys=/etc/agent-keys
work=/var/lib/agent-box
libexec=/usr/local/libexec/agent-box
repo=$work/central-hub
envdir=$work/rebuild-dev
inventory=$keys/rebuild-dev/inventory
export HOME=$work PATH=$libexec/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin
export TF_DATA_DIR=$work/tofu-data/rebuild-dev TF_IN_AUTOMATION=1
export ANSIBLE_COLLECTIONS_PATH=$libexec/collections ANSIBLE_HOME=$work/ansible-home

# What the box must hold before this wrapper can run. Each is put there through the keys wrapper
# or made by the agent_box role; the wrapper says which one is missing instead of failing later.
for f in "$keys/proxmox-dev.env" "$keys/dev-vms.tfvars"; do
  [[ -f $f ]] || { echo "rebuild: $f is missing" >&2; exit 1; }
done
[[ -d $inventory ]] || { echo "rebuild: the dev inventory $inventory is missing (docs/runbooks/set-up-the-agent-box.md, 'Rebuild dev from the box')" >&2; exit 1; }
[[ -x $libexec/ansible-venv/bin/ansible-playbook ]] || { echo "rebuild: Ansible is not installed; run the agent_box role" >&2; exit 1; }

# Only reviewed code on main runs with the keys, never a checkout a session can edit.
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
echo "rebuild: central-hub $(git -C "$repo" rev-parse --short HEAD)"

# Dev only, checked on the code just checked out: every node address in dev-vms.tfvars must sit in
# the dev VLAN (VLAN 30, from vlans.yml), and every inventory host must be one of those addresses,
# reached by plain ssh to ansible_host. Hosts that set another connection, a proxy or extra ssh
# arguments are refused. Nothing is printed except the count or the refused host.
ansible-inventory -i "$inventory/" --list | python3 -I -c "$(cat <<'PY'
import ipaddress, json, re, sys
tfvars, vlans = sys.argv[1], sys.argv[2]
def die(m):
    print("rebuild: " + m, file=sys.stderr); sys.exit(1)
import yaml
dev = [v["cidr"] for v in yaml.safe_load(open(vlans))["lab_vlans"] if v["id"] == 30]
if len(dev) != 1: die("vlans.yml has no single VLAN 30")
net = ipaddress.ip_network(dev[0])
addrs = set()
for line in open(tfvars):
    line = re.sub(r"(//|#).*", "", line)
    for a in re.findall(r'\baddress\s*=\s*"([^"]+)"', line):
        try: ip = ipaddress.ip_address(a)
        except ValueError: die("bad node address in dev-vms.tfvars")
        if ip not in net: die("a node address in dev-vms.tfvars is outside the dev VLAN; refusing")
        addrs.add(a)
if not addrs: die("no node addresses found in dev-vms.tfvars")
inv = json.load(sys.stdin)
hv = inv.get("_meta", {}).get("hostvars", {})
if not hv: die("the dev inventory lists no hosts")
bad = ("ansible_ssh_host", "ansible_ssh_common_args", "ansible_ssh_extra_args", "ansible_ssh_args",
       "ansible_ssh_executable", "ansible_ssh_pipelining_proxy")
for h, v in hv.items():
    if v.get("ansible_host") not in addrs: die("inventory host %s is not a dev node address; refusing" % h)
    if v.get("ansible_connection", "ssh") != "ssh": die("inventory host %s uses a connection other than ssh; refusing" % h)
    if any(k in v for k in bad): die("inventory host %s sets ssh host, proxy or extra arguments; refusing" % h)
print("rebuild: %d inventory hosts, all dev node addresses" % len(hv))
PY
)" "$keys/dev-vms.tfvars" "$repo/hosts/ansible/inventories/home/group_vars/all/vlans.yml" || exit 1

mkdir -p "$envdir" "$work/state"
chmod 700 "$envdir"
# The same state file as dev-vms, so the two wrappers agree about which VMs exist.
cat > "$envdir/rebuild.env" <<ENV
ENV_NAME=dev
VM_ID_MIN=250
VM_ID_MAX=257
TFVARS=$keys/dev-vms.tfvars
TFSTATE=$work/state/dev-vms.tfstate
TOFU_ENV=$keys/proxmox-dev.env
INVENTORY=$inventory/
STAGES="vms cluster storage restore gitops apps gateway checks"
RESTORE_HOOK='cd "\$REPO/hosts/ansible" && ansible-playbook -i "\$INVENTORY" playbooks/k8s-restore.yml'
RESTORE_CHECK_HOOK='cd "\$REPO/hosts/ansible" && ansible-playbook -i "\$INVENTORY" playbooks/k8s-restore.yml --tags restore_check'
ENV
chmod 600 "$envdir/rebuild.env"

exec bash "$repo/hosts/rebuild-k8s.sh" "$envdir" "${extra[@]}"
