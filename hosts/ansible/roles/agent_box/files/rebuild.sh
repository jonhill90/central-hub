#!/bin/bash
# /usr/local/libexec/agent-box/rebuild.sh: run the one-command rebuild of the DEV Kubernetes layer
# (hosts/rebuild-k8s.sh, docs/runbooks/rebuild-k8s-layer-with-one-command.md) from the agent box.
# It runs as user `keys` through sudo, so the session that asks for it never sees the Proxmox
# token, the node SSH key or the dev inventory. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/rebuild.sh up|rebuild|teardown|log
# up: all stages. rebuild: tear the dev VMs down first, then all stages. teardown: only the teardown.
# Dev only: the env file below fixes ENV_NAME=dev and the dev VM range 250-257, and rebuild-k8s.sh
# refuses a tfvars whose VM IDs fall outside it or whose node_vnet isn't "dev". Only code on main
# runs with the keys; there is no way to name another branch.
# log: print the newest run's stage lines and its PASS/FAIL lines, nothing else (the raw log can
# quote the realm and the nodes' output). It takes no argument and reads no other file.
set -euo pipefail
umask 077

if [[ ${1:-} == log && $# -eq 1 ]]; then
  newest=$(ls -1 /var/lib/agent-box/rebuild-dev/logs/rebuild-*.log 2>/dev/null | sort | tail -n 1)
  [[ -n $newest ]] || { echo "rebuild: no run has been logged yet" >&2; exit 1; }
  echo "run: ${newest##*/}"
  cat -- "$newest"
  sed -E 's/\x1b\[[0-9;]*m//g' -- "${newest%.log}.raw" 2>/dev/null | grep -E '(^|[^A-Za-z])(PASS|FAIL):' | cut -c1-200 | head -n 60 || true
  exit 0
fi

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
inv_src=$keys/rebuild-dev/inventory
inventory=$envdir/inventory
nodekey=$keys/rebuild-node-key
export HOME=$work PATH=$libexec/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin
export TF_DATA_DIR=$work/tofu-data/rebuild-dev TF_IN_AUTOMATION=1
export ANSIBLE_COLLECTIONS_PATH=$libexec/collections ANSIBLE_HOME=$work/ansible-home

# What the box must hold before this wrapper can run. Each is put there through the keys wrapper
# or made by the agent_box role; the wrapper says which one is missing instead of failing later.
for f in "$keys/proxmox-dev.env" "$keys/dev-vms.tfvars" "$keys/c1-backup.env" "$keys/azure-reader.env"; do
  [[ -f $f ]] || { echo "rebuild: $f is missing" >&2; exit 1; }
done
# The reader certificate must still be valid, or the restore stage fails after the VMs exist. A warning
# at 30 days left, so the renewal is not a surprise.
openssl x509 -checkend 0 -noout -in "$keys/azure-reader.env" > /dev/null \
  || { echo "rebuild: the reader certificate in $keys/azure-reader.env has expired or is unreadable" >&2; exit 1; }
openssl x509 -checkend 2592000 -noout -in "$keys/azure-reader.env" > /dev/null \
  || echo "rebuild: warning: the reader certificate expires within 30 days; renew it" >&2
[[ -d $inv_src ]] || { echo "rebuild: the dev inventory $inv_src is missing (docs/runbooks/set-up-the-agent-box.md, 'Rebuild dev from the box')" >&2; exit 1; }
[[ -x $libexec/ansible-venv/bin/ansible-playbook ]] || { echo "rebuild: Ansible is not installed; run the agent_box role" >&2; exit 1; }

# Only reviewed code on main runs with the keys, never a checkout a session can edit.
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
echo "rebuild: central-hub $(git -C "$repo" rev-parse --short HEAD)"

# The inventory that comes from the Mac reaches the nodes through a jump over root SSH to the
# Proxmox host. The box never holds root on the hypervisor, and its own network reaches the dev VLAN,
# so the box builds its own copy: the proxmox group and every ssh login, key and proxy setting are
# dropped, the box's own node key and plain ssh are set, and the gateway smoke test runs from the
# box itself (k8s_gateway_smoke_client). The Mac's private values (backup account, node name,
# gitops source) stay as they are. The guard below then checks the copy.
mkdir -p "$envdir" "$work/state"
chmod 700 "$envdir"
if [[ ! -f $nodekey ]]; then
  ssh-keygen -q -t ed25519 -N '' -C rebuild-dev-node -f "$nodekey"
fi
pub=$(cat "$nodekey.pub")
# The dev cluster's Secrets-at-rest key is the box's own, made once here and kept for later runs
# (the Mac's copy is a rehearsal key, not c1's). Never printed.
encfile=$keys/rebuild-encryption.key
if [[ ! -s $encfile ]]; then
  (umask 077; head -c 32 /dev/urandom | base64 > "$encfile")
fi
chmod 600 "$encfile"
# A copy of the tfvars whose node key is the box's own, so the nodes accept the box.
# The agents' token creates guests on their /vms/<id> ACL but may not add one to a pool (the module's pool_id is null) and clones only template 9001, the copy of template 9000 on VNet dev
# (hosts/terraform/home/bootstrap/agent-access.sh); the Mac's tfvars name 9000, for its root token.
awk -v pub="$pub" '/^[[:space:]]*node_ssh_public_key[[:space:]]*=/ { print "node_ssh_public_key = \"" pub "\""; next }
  /^[[:space:]]*(template_vm_id|pool_id)[[:space:]]*=/ { next } { print }' "$keys/dev-vms.tfvars" > "$envdir/dev-vms.tfvars"
printf '%s\n' 'template_vm_id = 9001' 'pool_id = null' >> "$envdir/dev-vms.tfvars"
grep -q '^node_ssh_public_key = "ssh-ed25519 ' "$envdir/dev-vms.tfvars" || { echo "rebuild: dev-vms.tfvars has no node_ssh_public_key line to set" >&2; exit 1; }
rm -rf "$inventory"
install -d -m 700 "$inventory"
python3 -I -c "$(cat <<'PY'
import sys, yaml
src, dst, key, known, keys = sys.argv[1:6]
d = yaml.safe_load(open(src))
DROP = {"ansible_ssh_common_args", "ansible_ssh_extra_args", "ansible_ssh_args", "ansible_ssh_private_key_file",
        "ansible_ssh_host", "ansible_ssh_executable", "ansible_connection", "ansible_ssh_pass", "ansible_password",
        "ansible_private_key_file", "ansible_host_key_checking",
        "k8s_gateway_smoke_client", "k8s_certs_smoke_client", "k8s_certs_smoke_root_file",
        "k8s_backup_env_file", "k8s_backup_azure_fixed_cert_file", "k8s_control_plane_encryption_key_file"}
def walk(n):
    if isinstance(n, dict):
        for k in list(n):
            if k in DROP: del n[k]
            elif k == "proxmox" and isinstance(n[k], dict) and ("hosts" in n[k] or "children" in n[k] or "vars" in n[k]): del n[k]
            else: walk(n[k])
    elif isinstance(n, list):
        for i in n: walk(i)
walk(d)
def find(n, name):
    if isinstance(n, dict):
        if name in n and isinstance(n[name], dict): return n[name]
        for v in n.values():
            r = find(v, name)
            if r is not None: return r
    return None
g = find(d, "k8s_nodes")
if g is None:
    print("rebuild: the dev inventory has no k8s_nodes group", file=sys.stderr); sys.exit(1)
v = g.setdefault("vars", {})
v["ansible_ssh_private_key_file"] = key
v["ansible_ssh_common_args"] = "-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=" + known
v["k8s_gateway_smoke_client"] = "localhost"
v["k8s_certs_smoke_client"] = "localhost"
v["k8s_certs_smoke_root_file"] = known.rsplit("/", 1)[0] + "/lab-root-ca.crt"
v["k8s_backup_env_file"] = keys + "/c1-backup.env"
v["k8s_backup_azure_fixed_cert_file"] = keys + "/azure-reader.env"
v["k8s_control_plane_encryption_key_file"] = keys + "/rebuild-encryption.key"
yaml.safe_dump(d, open(dst, "w"), default_flow_style=False)
PY
)" "$inv_src/hosts.yml" "$inventory/hosts.yml" "$nodekey" "$envdir/known_hosts" "$keys"
[[ -f $inventory/hosts.yml ]] || { echo "rebuild: could not build the box's dev inventory from $inv_src/hosts.yml" >&2; exit 1; }
chmod 600 "$inventory/hosts.yml"

# Dev only, checked on the code just checked out: every node address in dev-vms.tfvars must sit in
# the dev VLAN (VLAN 30, from vlans.yml), and every inventory host must be one of those addresses,
# reached by plain ssh to ansible_host. Hosts that set another connection, a proxy or extra ssh
# arguments are refused. Nothing is printed except the count or the refused host.
ansible-inventory -i "$inventory/" --list | python3 -I -c "$(cat <<'PY'
import ipaddress, json, re, sys
tfvars, vlans, nodekey, known = sys.argv[1:5]
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
bad = ("ansible_ssh_host", "ansible_ssh_extra_args", "ansible_ssh_args",
       "ansible_ssh_executable", "ansible_ssh_pipelining_proxy")
want_args = "-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=" + known
for h, v in hv.items():
    if v.get("ansible_host") not in addrs: die("inventory host %s is not a dev node address; refusing" % h)
    if v.get("ansible_connection", "ssh") != "ssh": die("inventory host %s uses a connection other than ssh; refusing" % h)
    if any(k in v for k in bad): die("inventory host %s sets ssh host, proxy or extra arguments; refusing" % h)
    if v.get("ansible_ssh_common_args") != want_args or v.get("ansible_ssh_private_key_file") != nodekey or "ansible_private_key_file" in v:
        die("inventory host %s has ssh arguments or a key other than the box's own; refusing" % h)
print("rebuild: %d inventory hosts, all dev node addresses" % len(hv))
PY
)" "$keys/dev-vms.tfvars" "$repo/hosts/ansible/inventories/home/group_vars/all/vlans.yml" "$nodekey" "$envdir/known_hosts" || exit 1

# The same state file as dev-vms, so the two wrappers agree about which VMs exist.
cat > "$envdir/rebuild.env" <<ENV
ENV_NAME=dev
VM_ID_MIN=250
VM_ID_MAX=257
TFVARS=$envdir/dev-vms.tfvars
TFSTATE=$work/state/dev-vms.tfstate
TOFU_ENV=$keys/proxmox-dev.env
INVENTORY=$inventory/
STAGES="vms cluster storage restore gitops apps gateway checks"
RESTORE_HOOK='cd "\$REPO/hosts/ansible" && ansible-playbook -i "\$INVENTORY" playbooks/k8s-restore.yml'
RESTORE_CHECK_HOOK='cd "\$REPO/hosts/ansible" && ansible-playbook -i "\$INVENTORY" playbooks/k8s-restore.yml --tags restore_check'
ENV
chmod 600 "$envdir/rebuild.env"

exec bash "$repo/hosts/rebuild-k8s.sh" "$envdir" "${extra[@]}"
