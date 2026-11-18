#!/bin/bash
# /usr/local/libexec/agent-box/c1-ansible.sh: run one named Ansible playbook against prod's c1 from the agent box, so the
# change to c1 leaves the Mac. It runs as user `keys` through sudo, with the box's own prod node key (the key openbao-prod
# makes), so the session never sees a key, a values file or the inventory. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/c1-ansible.sh list|check <name>|apply <name> <clearance id>|log
# list    the names this wrapper runs.
# check   read-only: the playbook with --check --diff. It changes nothing on c1.
# apply   the playbook for real. <clearance id> is the cmsg_ id of the reviewer's clearance of the head that is on main
#         (D-0042 rule 1); it goes into the log, and the wrapper cannot read the chat to check it.
# log     the newest run's lines: the action, the commit, the clearance id, and the PASS, FAIL, task and recap lines.
# Names are fixed in the table below, each one playbook with no extra argument from the session. Only code on main runs,
# in this wrapper's own checkout. The inventory is the box's copy from the controller (<keys>/prod/inventory-hosts.yml); this
# wrapper builds its own copy with the box's node key and plain ssh, and refuses any host that sets a proxy, another
# connection or another key, or is labelled another env than prod. A name that needs a private values file the box does not
# hold stops with that file's name; the controller's prod-files run puts it there.
set -euo pipefail
umask 077

keys=/etc/agent-keys
work=/var/lib/agent-box
libexec=/usr/local/libexec/agent-box
repo=$work/checkouts/c1-ansible   # this wrapper's own checkout of central-hub
envdir=$work/c1-ansible
logs=$envdir/logs
inv_src=$keys/prod/inventory-hosts.yml
inventory=$envdir/inventory
nodekey=$keys/prod-node-key
export HOME=$work PATH=$libexec/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin
export ANSIBLE_COLLECTIONS_PATH=$libexec/collections ANSIBLE_HOME=$work/ansible-home

# name -> playbook (under hosts/ansible), and the private file it needs on the box (empty: none) with the variable that names it.
declare -A playbook=([identity]=playbooks/k8s-identity.yml)
declare -A needs_file=([identity]="$keys/prod/identity.env")
declare -A needs_var=([identity]=k8s_identity_values_file)
# Fixed extra variables per name. identity never replaces realm lab on prod: the role's default deletes the realm and
# imports it again when its code changes, which on prod ends every sign-in and drops enrolled one-time codes. With false
# the realm is only made when missing; a client is added in place by the role's clients tag.
declare -A fixed_vars=([identity]=k8s_identity_realm_replace=false)
# Tags per name. identity runs every task plus the clients tag, which is off by default. The tag acts only on the clients in
# k8s_identity_ensure_clients (empty by default), so the wrapper names one: proxmox, the client the realm gained after prod's
# realm was made. It is added in place, with no realm replace. Name another client here, in its own pull request, to add it.
declare -A fixed_tags=([identity]="all,clients")
declare -A fixed_json=([identity]='{"k8s_identity_ensure_clients":["proxmox"]}')

usage() { echo "usage: c1-ansible list|check <name>|apply <name> <clearance id>|log" >&2; exit 2; }
action=${1:-} name='' clearance=''
case $action in
  list | log) [[ $# -eq 1 ]] || usage ;;
  check) [[ $# -eq 2 ]] || usage; name=$2 ;;
  apply)
    [[ $# -eq 3 ]] || usage
    name=$2 clearance=$3
    [[ $clearance =~ ^cmsg_[A-Za-z0-9]{20,60}$ ]] || { echo "c1-ansible: the clearance id is the reviewer's message id, cmsg_<letters and digits>" >&2; exit 2; }
    ;;
  *) usage ;;
esac
if [[ -n $name ]]; then
  [[ $name =~ ^[a-z][a-z0-9-]{0,30}$ && -n ${playbook[$name]:-} ]] || { echo "c1-ansible: '$name' is not a name this wrapper runs (c1-ansible list)" >&2; exit 2; }
fi

if [[ $action == list ]]; then printf '%s\n' "${!playbook[@]}" | sort; exit 0; fi
if [[ $action == log ]]; then
  newest=$(find "$logs" -maxdepth 1 -name 'run-*.log' 2>/dev/null | sort | tail -n 1)
  [[ -n $newest ]] || { echo "c1-ansible: no run has been logged yet" >&2; exit 1; }
  echo "run: ${newest##*/}"
  sed -E 's/\x1b\[[0-9;]*m//g' -- "$newest" | grep -E '^(c1-ansible:|PLAY RECAP|TASK \[|.*(PASS|FAIL|SKIP):|fatal:|[^ ]+ +: ok=)' | cut -c1-200 | tail -n 60 || true
  exit 0
fi

[[ -f $nodekey ]] || { echo "c1-ansible: no prod node key yet; run openbao-prod key, and put its public half on prod's nodes" >&2; exit 1; }
[[ -f $inv_src ]] || { echo "c1-ansible: the prod inventory $inv_src is missing (the controller's prod-files run copies it)" >&2; exit 1; }
[[ -x $libexec/ansible-venv/bin/ansible-playbook ]] || { echo "c1-ansible: Ansible is not installed; run the agent_box role" >&2; exit 1; }
extra=()
if [[ -n ${needs_file[$name]:-} ]]; then
  [[ -s ${needs_file[$name]} ]] || { echo "c1-ansible: ${needs_file[$name]} is missing; the controller's prod-files run puts it there" >&2; exit 1; }
  extra=(-e "${needs_var[$name]}=${needs_file[$name]}")
fi
[[ -n ${fixed_vars[$name]:-} ]] && extra+=(-e "${fixed_vars[$name]}")
[[ -n ${fixed_tags[$name]:-} ]] && extra+=(--tags "${fixed_tags[$name]}")
[[ -n ${fixed_json[$name]:-} ]] && extra+=(-e "${fixed_json[$name]}")

mkdir -p "$envdir" "$logs" "$work/state"
chmod 700 "$envdir"
exec 9>"$work/state/c1-ansible.lock"
flock -n 9 || { echo "c1-ansible: another c1-ansible run is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
commit=$(git -C "$repo" rev-parse --short HEAD)
[[ -f $repo/hosts/ansible/${playbook[$name]} ]] || { echo "c1-ansible: ${playbook[$name]} is not in this commit of main" >&2; exit 1; }

# The box's copy of the prod inventory: every ssh login, key and proxy setting dropped, and the proxmox group with them; the
# box's node key and plain ssh set. Nothing is printed but a count or the refused host.
rm -rf -- "$inventory"
install -d -m 700 "$inventory"
python3 -I -c "$(cat <<'PY'
import sys, yaml
src, dst, key, known = sys.argv[1:5]
def die(m):
    print("c1-ansible: " + m, file=sys.stderr); sys.exit(1)
d = yaml.safe_load(open(src))
DROP = {"ansible_ssh_common_args", "ansible_ssh_extra_args", "ansible_ssh_args", "ansible_ssh_private_key_file",
        "ansible_ssh_host", "ansible_ssh_executable", "ansible_connection", "ansible_ssh_pass", "ansible_password",
        "ansible_private_key_file", "ansible_host_key_checking"}
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
if g is None: die("the prod inventory has no k8s_nodes group")
v = g.setdefault("vars", {})
v["ansible_ssh_private_key_file"] = key
v["ansible_ssh_common_args"] = "-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=" + known
yaml.safe_dump(d, open(dst, "w"), default_flow_style=False)
PY
)" "$inv_src" "$inventory/hosts.yml" "$nodekey" "$envdir/known_hosts" || exit 1
chmod 600 "$inventory/hosts.yml"

# Every k8s node: plain ssh to ansible_host with the box's key and nothing else; no host labelled another env than prod.
ansible-inventory -i "$inventory/" --list | python3 -I -c "$(cat <<'PY'
import json, sys
nodekey, known = sys.argv[1:3]
def die(m):
    print("c1-ansible: " + m, file=sys.stderr); sys.exit(1)
inv = json.load(sys.stdin)
hv = inv.get("_meta", {}).get("hostvars", {})
nodes = set(inv.get("k8s_nodes", {}).get("hosts", []))
for child in inv.get("k8s_nodes", {}).get("children", []):
    nodes.update(inv.get(child, {}).get("hosts", []))
if not nodes: die("the prod inventory lists no k8s_nodes hosts")
want = "-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=" + known
bad = ("ansible_ssh_host", "ansible_ssh_extra_args", "ansible_ssh_args", "ansible_ssh_executable", "ansible_private_key_file")
for h in nodes:
    v = hv.get(h, {})
    if not v.get("ansible_host"): die("inventory host %s has no ansible_host; refusing" % h)
    if v.get("ansible_connection", "ssh") != "ssh": die("inventory host %s uses a connection other than ssh; refusing" % h)
    if any(k in v for k in bad): die("inventory host %s sets ssh host, proxy or extra arguments; refusing" % h)
    if v.get("ansible_ssh_common_args") != want or v.get("ansible_ssh_private_key_file") != nodekey:
        die("inventory host %s has ssh arguments or a key other than the box's own; refusing" % h)
    env = (v.get("k8s_gitops_cluster_labels") or {}).get("env", "prod")
    if env != "prod": die("inventory host %s is labelled env %s, not prod; refusing" % (h, env))
print("c1-ansible: %d prod nodes, plain ssh with the box's key" % len(nodes))
PY
)" "$nodekey" "$envdir/known_hosts" || exit 1

stamp=$(date -u +%Y%m%dT%H%M%SZ)
log=$logs/run-$stamp.log
exec > >(tee -a "$log") 2>&1
echo "c1-ansible: $action $name at central-hub $commit${clearance:+, clearance $clearance}"
mode=(--check --diff)
[[ $action == apply ]] && mode=()
(cd "$repo/hosts/ansible" && ansible-playbook -i "$inventory/" "${playbook[$name]}" "${extra[@]}" "${mode[@]}")
echo "c1-ansible: $action $name done"
