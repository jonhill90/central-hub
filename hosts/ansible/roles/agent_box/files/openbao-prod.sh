#!/bin/bash
# /usr/local/libexec/agent-box/openbao-prod.sh: turn on the secrets store inside prod's c1 (D-0058) from the agent box,
# with the box's own prod node key, so no Mac runs it (docs/runbooks/set-up-the-secrets-store.md, "On prod").
# It runs as user `keys` through sudo, so the session never sees the node key, the seal key or the admin IDs.
# Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/openbao-prod.sh key|check|seal <tap id>|gitops|handover|log
# key       makes the box's prod node key once (/etc/agent-keys/prod-node-key, ed25519, never replaced) and prints its
#           public half. Putting it on prod's nodes gives the agents a root login there, a new access right, so that step
#           waits for the owner's tap (D-0042 rule 6) and is done once, by a run that already reaches the nodes.
# check     read-only: for each prod node in the inventory, ssh as root with that key, BatchMode, 10 s: reached, the key
#           refused, or no answer (a firewall), by node name. Nothing else runs.
# seal      puts prod's seal key on the node openbaoSealNode names (playbooks/k8s-openbao-seal.yml), D-0058 rule 3. Putting
#           the prod key on a node is a secrets step, so the owner's tap comes first (D-0042 rule 6): <tap id> is the cmsg_ id
#           of that tap, and it goes into the log. The key is made once from 32 random bytes and kept only as a SOPS copy
#           (/etc/agent-keys/prod/openbao-seal.key.sops.json, the box's age identity), never replaced: a new key would make
#           every snapshot unreadable. Each run decrypts it into a private folder in memory, removed when the run ends.
# gitops    playbooks/k8s-gitops.yml --tags source: the root Application's parameters only, with the in-cluster store on
#           (k8s_gitops_source_openbao_in_cluster, _seal_node, _box_cidr), so Argo CD makes openbao-store, openbao and the
#           secret-store app's store `openbao`. Argo CD's install is left alone.
# handover  playbooks/k8s-openbao-handover.yml with prod's admin AppRole IDs (/etc/agent-keys/prod/openbao-admin-*, made
#           once by the same rule as secrets-store.sh, never printed).
# log       the newest run's lines: the action, the commit, the tap id, and the PASS, FAIL, SKIP and play-recap lines.
# Settings (agent_box_openbao_prod, private, in <work>/openbao-prod.json): seal_node (a k8s_nodes host of the prod inventory,
# its Kubernetes node name), store_host (the store's name as the box reaches it; secrets-store-prod checks its own address
# against it) and box_cidr (the box's address as a /32; empty until the box's path to the store is set, and the hand-over
# skips meanwhile). The prod inventory is the box's copy from the controller (<keys>/prod/inventory-hosts.yml,
# prod_files.yml); this wrapper builds its own copy with the box's node key and plain ssh, and refuses any host that sets
# a proxy, another connection or another key. Only code on main runs with the keys.
set -euo pipefail
umask 077

keys=/etc/agent-keys
work=/var/lib/agent-box
libexec=/usr/local/libexec/agent-box
repo=$work/checkouts/openbao-prod   # this wrapper's own checkout of central-hub
envdir=$work/openbao-prod
logs=$envdir/logs
inv_src=$keys/prod/inventory-hosts.yml
inventory=$envdir/inventory
nodekey=$keys/prod-node-key
store_keys=$keys/prod
settings=$work/openbao-prod.json
export HOME=$work PATH=$libexec/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin
export ANSIBLE_COLLECTIONS_PATH=$libexec/collections ANSIBLE_HOME=$work/ansible-home

usage() { echo "usage: openbao-prod key|check|seal <tap id>|gitops|handover|log" >&2; exit 2; }
action=${1:-}
tap=''
case $action in
  key | check | gitops | handover | log) [[ $# -eq 1 ]] || usage ;;
  seal)
    [[ $# -eq 2 ]] || usage
    tap=$2
    [[ $tap =~ ^cmsg_[A-Za-z0-9]{20,60}$ ]] || { echo "openbao-prod: the tap id is the owner's tap message id, cmsg_<letters and digits>" >&2; exit 2; }
    ;;
  *) usage ;;
esac

if [[ $action == log ]]; then
  newest=$(ls -1 "$logs"/run-*.log 2>/dev/null | sort | tail -n 1 || true)
  [[ -n $newest ]] || { echo "openbao-prod: no run has been logged yet" >&2; exit 1; }
  echo "run: ${newest##*/}"
  sed -E 's/\x1b\[[0-9;]*m//g' -- "$newest" | grep -E '^(openbao-prod:|PLAY RECAP|.*(PASS|FAIL|SKIP):|[^ ]+ +: ok=)' | cut -c1-200 | head -n 60 || true
  exit 0
fi

mkdir -p "$envdir" "$logs" "$work/state"
chmod 700 "$envdir"

if [[ $action == key ]]; then
  [[ -f $nodekey ]] || ssh-keygen -q -t ed25519 -N '' -C openbao-prod-node -f "$nodekey"
  echo "openbao-prod: the box's prod node key, public half ($nodekey.pub), for root's authorized_keys on prod's nodes:"
  cat -- "$nodekey.pub"
  exit 0
fi

[[ -f $nodekey ]] || { echo "openbao-prod: no prod node key yet; run openbao-prod key, and put its public half on prod's nodes" >&2; exit 1; }
[[ -f $inv_src ]] || { echo "openbao-prod: the prod inventory $inv_src is missing (the controller's prod-files run copies it)" >&2; exit 1; }
[[ -f $settings ]] || { echo "openbao-prod: $settings is missing; set agent_box_openbao_prod in the inventory and run the agent_box role" >&2; exit 1; }
[[ -x $libexec/ansible-venv/bin/ansible-playbook ]] || { echo "openbao-prod: Ansible is not installed; run the agent_box role" >&2; exit 1; }

# One run at a time, in its own checkout of main.
exec 9>"$work/state/openbao-prod.lock"
flock -n 9 || { echo "openbao-prod: another openbao-prod run is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
commit=$(git -C "$repo" rev-parse --short HEAD)

# The box's own copy of the prod inventory: every ssh login, key and proxy setting dropped, and the proxmox group
# with them; the box's node key and plain ssh set; the store's settings added. A host whose name is the seal node must
# exist. Nothing is printed but a count or the refused host.
rm -rf -- "$inventory"
install -d -m 700 "$inventory"
python3 -I -c "$(cat <<'PY'
import ipaddress, json, os, sys, yaml
src, dst, key, known, settings, stable = sys.argv[1:7]
s = json.load(open(settings))
seal, store, cidr = s.get("seal_node") or "", s.get("store_host") or "", s.get("box_cidr") or ""
def die(m):
    print("openbao-prod: " + m, file=sys.stderr); sys.exit(1)
if not seal: die("the settings have no seal_node")
if not store: die("the settings have no store_host")
if cidr:
    try: n = ipaddress.ip_network(cidr, strict=False)
    except ValueError: die("box_cidr must be one address as a /32, not loopback")
    if n.prefixlen != 32 or n.is_loopback: die("box_cidr must be one address as a /32, not loopback")
d = yaml.safe_load(open(src))
DROP = {"ansible_ssh_common_args", "ansible_ssh_extra_args", "ansible_ssh_args", "ansible_ssh_private_key_file",
        "ansible_ssh_host", "ansible_ssh_executable", "ansible_connection", "ansible_ssh_pass", "ansible_password",
        "ansible_private_key_file", "ansible_host_key_checking",
        "k8s_gitops_source_openbao_address", "k8s_gitops_source_openbao_ca_file", "k8s_gitops_source_openbao_measure",
        "k8s_gitops_source_openbao_in_cluster", "k8s_gitops_source_openbao_seal_node", "k8s_gitops_source_openbao_box_cidr",
        "k8s_gitops_source_openbao_store_host"}
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
names = set()
def hosts(n):
    if isinstance(n, dict):
        for k, v in n.items():
            if k == "hosts" and isinstance(v, dict): names.update(v)
            else: hosts(v)
hosts(g)
if seal not in names: die("seal_node is not a k8s_nodes host of the prod inventory")
v = g.setdefault("vars", {})
v["ansible_ssh_private_key_file"] = key
v["ansible_ssh_common_args"] = "-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=" + known
v["k8s_gitops_source_openbao_in_cluster"] = True
v["k8s_gitops_source_openbao_seal_node"] = seal
v["k8s_gitops_source_openbao_store_host"] = store
if cidr: v["k8s_gitops_source_openbao_box_cidr"] = cidr
# Once rebuild-prod has built prod again, its local-path StorageClass names folders <namespace>/<claim>; a
# StorageClass's parameters can't change in place, so every later render keeps that setting.
if os.path.exists(stable): v["k8s_gitops_source_local_path_stable_folders"] = True
yaml.safe_dump(d, open(dst, "w"), default_flow_style=False)
PY
)" "$inv_src" "$inventory/hosts.yml" "$nodekey" "$envdir/known_hosts" "$settings" "$work/state/prod-stable-folders" || exit 1
chmod 600 "$inventory/hosts.yml"

# Every host: plain ssh to ansible_host with the box's key and nothing else; no host labelled another env than prod.
ansible-inventory -i "$inventory/" --list | python3 -I -c "$(cat <<'PY'
import json, sys
nodekey, known = sys.argv[1:3]
def die(m):
    print("openbao-prod: " + m, file=sys.stderr); sys.exit(1)
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
print("openbao-prod: %d prod nodes, plain ssh with the box's key" % len(nodes))
PY
)" "$nodekey" "$envdir/known_hosts" || exit 1

stamp=$(date -u +%Y%m%dT%H%M%SZ)
log=$logs/run-$stamp.log
exec > >(tee -a "$log") 2>&1
echo "openbao-prod: $action at central-hub $commit${tap:+, owner tap $tap}"
ap() { (cd "$repo/hosts/ansible" && ansible-playbook -i "$inventory/" "$@"); }

case $action in
  check)
    # One ssh per node: reached, the key refused, or no answer. Exit 0 either way; the lines are the result.
    ansible-inventory -i "$inventory/" --list | python3 -I -c "$(cat <<'PY'
import json, sys
inv = json.load(sys.stdin)
hv = inv["_meta"]["hostvars"]
nodes = set(inv.get("k8s_nodes", {}).get("hosts", []))
for c in inv.get("k8s_nodes", {}).get("children", []): nodes.update(inv.get(c, {}).get("hosts", []))
for h in sorted(nodes): print(h, hv[h]["ansible_host"], hv[h].get("ansible_user", "root"))
PY
)" |
    while read -r name host user; do
      if out=$(ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
                 -o UserKnownHostsFile="$envdir/known_hosts" -i "$nodekey" "$user@$host" true 2>&1); then
        echo "openbao-prod: check $name: reached"
      elif [[ $out == *"Permission denied"* ]]; then echo "openbao-prod: check $name: answered, the key refused"
      else echo "openbao-prod: check $name: no answer: ${out:0:80}"; fi
    done
    ;;
  seal)
    identity=$keys/secrets-bundle/age-identity.txt
    [[ -s $identity ]] || { echo "openbao-prod: $identity is missing; set agent_box_secrets_bundle and run the agent_box role" >&2; exit 1; }
    seal_sops=$store_keys/openbao-seal.key.sops.json
    find /dev/shm -maxdepth 1 -name 'openbao-prod-seal.*' -user "$(id -u)" -exec rm -rf -- {} +
    seal_tmp=$(mktemp -d /dev/shm/openbao-prod-seal.XXXXXX)
    trap 'rm -rf -- "$seal_tmp"' EXIT
    trap 'exit 1' INT TERM HUP
    mkdir -p "$store_keys"
    if [[ ! -e $seal_sops ]]; then
      openssl rand -out "$seal_tmp/new.key" 32
      recipient=$("$libexec/age-keygen" -y "$identity")
      [[ $recipient =~ ^age1[0-9a-z]{58}$ ]] || { echo "openbao-prod: the box's identity gives no age recipient" >&2; exit 1; }
      "$libexec/sops" encrypt --input-type binary --output-type json --age "$recipient" --output "$seal_sops.part" "$seal_tmp/new.key" ||
        { rm -f -- "$seal_sops.part"; echo "openbao-prod: sops could not encrypt the seal key" >&2; exit 1; }
      if ! SOPS_AGE_KEY_FILE=$identity "$libexec/sops" decrypt --input-type json --output-type binary \
           --output "$seal_tmp/back.key" "$seal_sops.part" || ! cmp -s "$seal_tmp/back.key" "$seal_tmp/new.key"; then
        rm -f -- "$seal_sops.part"; echo "openbao-prod: the seal key's SOPS copy does not read back to the same bytes" >&2; exit 1
      fi
      mv -- "$seal_sops.part" "$seal_sops"
      rm -f -- "$seal_tmp/new.key" "$seal_tmp/back.key"
      echo "openbao-prod: a new prod seal key, kept only as its SOPS copy in the keys folder"
    fi
    SOPS_AGE_KEY_FILE=$identity "$libexec/sops" decrypt --input-type json --output-type binary \
      --output "$seal_tmp/openbao-seal.key" "$seal_sops" || { echo "openbao-prod: $seal_sops does not decrypt with the box's identity" >&2; exit 1; }
    [[ $(wc -c < "$seal_tmp/openbao-seal.key") -eq 32 ]] || { echo "openbao-prod: the seal key in $seal_sops is not 32 bytes" >&2; exit 1; }
    ap playbooks/k8s-openbao-seal.yml -e "openbao_seal_key_file=$seal_tmp/openbao-seal.key"
    ;;
  gitops)
    ap playbooks/k8s-gitops.yml --tags source
    ;;
  handover)
    mkdir -p "$store_keys"
    [[ -f $store_keys/openbao-admin-role-id ]] || openssl rand -hex 24 | tr -d '\n' > "$store_keys/openbao-admin-role-id"
    [[ -f $store_keys/openbao-admin-secret-id ]] || openssl rand -hex 24 | tr -d '\n' > "$store_keys/openbao-admin-secret-id"
    ap playbooks/k8s-openbao-handover.yml -e "openbao_admin_role_id_file=$store_keys/openbao-admin-role-id" \
      -e "openbao_admin_secret_id_file=$store_keys/openbao-admin-secret-id"
    ;;
esac
echo "openbao-prod: $action done"
