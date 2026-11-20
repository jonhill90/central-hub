#!/bin/bash
# /usr/local/libexec/agent-box/openbao-prod.sh: turn on the secrets store inside prod's c1 (D-0058) from the agent box,
# with the box's own prod node key, so no Mac runs it (docs/runbooks/set-up-the-secrets-store.md, "On prod").
# It runs as user `keys` through sudo, so the session never sees the node key, the seal key or the admin IDs.
# Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/openbao-prod.sh key|check|seal <tap id>|seal-copy <tap id>|l2-policy|gitops|ca|handover|refresh <tap id>|reset-failed-start <tap id>|drop-box-path <tap id>|admin-firewall-check|admin-firewall <tap id>|log
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
# seal-copy for a store whose seal key was put on its node by another run (the Mac's): reads that key off the seal node
#           over ssh into the same private folder in memory, and keeps it as the same SOPS copy, read back before it is
#           kept, never printed. Copying a secret onto the box is a secrets step, so <tap id> is the owner's tap. With a
#           SOPS copy already kept, it only compares the two and fails if they differ; nothing is replaced.
# l2-policy playbooks/k8s.yml --tags lb on the first control plane only: role k8s_control_plane's load-balancer pool and
#           general L2 announcement policy, which leaves out Services labelled central-hub/l2-policy (D-0062). Run it once
#           before the settings get admin_address, so that policy never announces the admin address from every node.
# gitops    playbooks/k8s-gitops.yml --tags source: the root Application's parameters only, with the in-cluster store on
#           (k8s_gitops_source_openbao_in_cluster, _seal_node, _box_cidr, _store_host, _admin_address), so Argo CD makes
#           openbao-store, openbao and the secret-store app's store `openbao`. Argo CD's install is left alone.
# ca        the CA the box checks prod's store against on its admin path (TLS ends at OpenBao, D-0062): ca.crt of Secret openbao/openbao-tls, a public certificate, written to <keys>/prod/secrets-store-ca.crt
#           only if it is one PEM certificate. Run it after gitops, and again after a rebuild, which makes a new CA.
# handover  playbooks/k8s-openbao-handover.yml with prod's admin AppRole IDs (/etc/agent-keys/prod/openbao-admin-*, made
#           once by the same rule as secrets-store.sh, never printed).
# refresh   playbooks/k8s-openbao-refresh.yml, after handover: the store's policies and its admin login's address
#           binding set again from git. Self-init makes them only at the store's first start, and prod's came before
#           openbaoMarkEnv reached it, so its snapshot policy reads dev's mark. With admin_address in the settings the play
#           signs in as the admin from the box over the admin address (prod's admin is bound to the box's /32), checked
#           against <keys>/prod/secrets-store-ca.crt (run ca first); without one, from inside OpenBao's pod, for a store
#           still bound to 127.0.0.1/32. It writes each policy that differs from ConfigMap openbao-policies, binds role admin
#           to box_cidr, and prints the changed policy names and PASS. It changes access rights
#           (D-0042 rule 6): <tap id> is the owner's go (D-0061 rule 3: the message id of his standing go), logged as for seal.
# reset-failed-start  clears a first start that stopped in self-init (the pod's log says "self-initialization failed:
#           refusing to unseal"), so the store starts clean. It refuses unless that line is in the pod's log (this run's or
#           the last one's), the pod is not Ready and `bao status` does not say the store is initialized. It deletes only
#           the pod openbao-0 and the claim data-openbao-0 in namespace openbao, and prints both before and after. It
#           replaces a hand delete; a store that was ever initialized is never touched. <tap id> is the owner's tap on a
#           card naming this step and the commit: it deletes a claim (D-0042 rule 6); it is checked and logged as for seal.
# drop-box-path  deletes the store's old Gateway path on prod (ListenerSet, TLSRoute and CiliumNetworkPolicy openbao-box in
#           namespace openbao), which left git with the passthrough paths and stays because openbao-store does not prune.
#           It deletes only those of the three that Argo CD's own status of Application openbao-store marks requiresPruning
#           (no longer in git), refuses if any of them is still in git, and prints all three before and after. Deleting is a
#           D-0042 rule 6 step: <tap id> is the owner's go (D-0061 rule 3: the message id of his standing go), logged as for seal.
# admin-firewall-check  read-only: playbooks/k8s-openbao-admin-firewall.yml with --check --diff on prod's nodes. It prints,
#           per node, "admin-fw: policy openbao-admin present|absent, rule for <box /32> to tcp 8200 present|absent" (read that
#           line: the add tasks are skipped in check mode, so the recap's changed count is 0 either way), and changes nothing.
# admin-firewall  the same playbook for real: on each prod node, firewalld policy openbao-admin from the lab zone to any
#           zone, one rich rule, the box's /32 (box_cidr) to tcp 8200, accept, so the store's admin path crosses the node's
#           forward path (D-0062; the dev rebuild runs the same play in stage gateway). Without box_cidr or admin_address in
#           the settings it changes nothing and says SKIP. A node firewall change is the owner's go (D-0036 rule 8): <tap id>
#           is his go (D-0061 rule 3: the message id of his standing go), logged as for seal.
# log       the newest run's lines: the action, the commit, the tap id, and the PASS, FAIL, SKIP and play-recap lines.
# Settings (agent_box_openbao_prod, private, in <work>/openbao-prod.json): seal_node (a k8s_nodes host of the prod inventory,
# its Kubernetes node name), store_host (the store's name as the box reaches it; secrets-store-prod checks its own address
# against it), box_cidr (the box's address as a /32; empty until the box's path to the store is set, and the hand-over
# skips meanwhile) and admin_address (the store's admin address, one address of prod's load-balancer pool, which needs
# box_cidr; empty: no admin path, D-0062). The prod inventory is the box's copy from the controller (<keys>/prod/inventory-hosts.yml,
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

usage() { echo "usage: openbao-prod key|check|seal <tap id>|seal-copy <tap id>|l2-policy|gitops|ca|handover|refresh <tap id>|reset-failed-start <tap id>|drop-box-path <tap id>|admin-firewall-check|admin-firewall <tap id>|log" >&2; exit 2; }
action=${1:-}
tap=''
case $action in
  key | check | l2-policy | gitops | ca | handover | admin-firewall-check | log) [[ $# -eq 1 ]] || usage ;;
  seal | seal-copy | refresh | reset-failed-start | drop-box-path | admin-firewall)
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
admin = s.get("admin_address") or ""
if admin:
    try: a = ipaddress.ip_address(admin)
    except ValueError: a = None
    if a is None or a.version != 4 or a.is_loopback: die("admin_address must be one IPv4 address, not loopback")
    if not cidr: die("admin_address needs box_cidr: only the box's /32 may reach the admin address")
d = yaml.safe_load(open(src))
DROP = {"ansible_ssh_common_args", "ansible_ssh_extra_args", "ansible_ssh_args", "ansible_ssh_private_key_file",
        "ansible_ssh_host", "ansible_ssh_executable", "ansible_connection", "ansible_ssh_pass", "ansible_password",
        "ansible_private_key_file", "ansible_host_key_checking",
        "k8s_gitops_source_openbao_address", "k8s_gitops_source_openbao_ca_file", "k8s_gitops_source_openbao_measure",
        "k8s_gitops_source_openbao_in_cluster", "k8s_gitops_source_openbao_seal_node", "k8s_gitops_source_openbao_box_cidr",
        "k8s_gitops_source_openbao_store_host", "k8s_gitops_source_openbao_admin_address", "k8s_gitops_source_notebook_runner",
        "k8s_gitops_source_app_secrets_store"}
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
# The notebook CI runner pod is prod's only (docs/runbooks/run-the-notebook-runner-on-c1.md).
v["k8s_gitops_source_notebook_runner"] = True
v["k8s_gitops_source_openbao_seal_node"] = seal
v["k8s_gitops_source_openbao_store_host"] = store
# The apps read their secrets through store `openbao` (plan step 8a, D-0058 rule 8), once `secrets-store-prod put-apps`
# and `compare` have passed (set-up-the-secrets-store.md, "Moving them"). Prod has the store on, so this is always valid here.
v["k8s_gitops_source_app_secrets_store"] = "openbao"
if cidr: v["k8s_gitops_source_openbao_box_cidr"] = cidr
if admin: v["k8s_gitops_source_openbao_admin_address"] = admin
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
# kc <kubectl arguments>: kubectl on the first control-plane node with its admin kubeconfig, through Ansible. It prints the
# command's output and returns its exit code (ansible.posix.json, pinned in hosts/ansible/requirements.yml, gives the run as
# one JSON document), the same way hosts/rebuild-k8s.sh does.
kc() {
  local json rc=0
  json=$(cd "$repo/hosts/ansible" && ANSIBLE_LOAD_CALLBACK_PLUGINS=1 ANSIBLE_STDOUT_CALLBACK=ansible.posix.json \
    ansible 'k8s_control_plane[0]' -i "$inventory/" -b -m ansible.builtin.command \
    -a "kubectl --kubeconfig /etc/kubernetes/admin.conf $*") || rc=$?
  printf '%s' "$json" | python3 -I -c '
import json, sys
try:
    res = list(json.load(sys.stdin)["plays"][0]["tasks"][0]["hosts"].values())[0]
except Exception as e:
    print("kc: no result from Ansible: %s" % e, file=sys.stderr); sys.exit(1)
if res.get("stdout"): print(res["stdout"])
err = res.get("stderr") or ("" if "rc" in res else res.get("msg", ""))
if err: print(err, file=sys.stderr)
sys.exit(res.get("rc", 1))
' || rc=$?
  return "$rc"
}

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
  seal | seal-copy)
    identity=$keys/secrets-bundle/age-identity.txt
    [[ -s $identity ]] || { echo "openbao-prod: $identity is missing; set agent_box_secrets_bundle and run the agent_box role" >&2; exit 1; }
    seal_sops=$store_keys/openbao-seal.key.sops.json
    find /dev/shm -maxdepth 1 -name 'openbao-prod-seal.*' -user "$(id -u)" -exec rm -rf -- {} +
    seal_tmp=$(mktemp -d /dev/shm/openbao-prod-seal.XXXXXX)
    trap 'rm -rf -- "$seal_tmp"' EXIT
    trap 'exit 1' INT TERM HUP
    mkdir -p "$store_keys"
    # Keep $1 (32 bytes) as the SOPS copy, only if it reads back to the same bytes.
    keep() {
      local recipient
      recipient=$("$libexec/age-keygen" -y "$identity")
      [[ $recipient =~ ^age1[0-9a-z]{58}$ ]] || { echo "openbao-prod: the box's identity gives no age recipient" >&2; exit 1; }
      "$libexec/sops" encrypt --input-type binary --output-type json --age "$recipient" --output "$seal_sops.part" "$1" ||
        { rm -f -- "$seal_sops.part"; echo "openbao-prod: sops could not encrypt the seal key" >&2; exit 1; }
      if ! SOPS_AGE_KEY_FILE=$identity "$libexec/sops" decrypt --input-type json --output-type binary \
           --output "$seal_tmp/back.key" "$seal_sops.part" || ! cmp -s "$seal_tmp/back.key" "$1"; then
        rm -f -- "$seal_sops.part"; echo "openbao-prod: the seal key's SOPS copy does not read back to the same bytes" >&2; exit 1
      fi
      mv -- "$seal_sops.part" "$seal_sops"
      rm -f -- "$seal_tmp/back.key"
    }
    if [[ $action == seal-copy ]]; then
      # The seal node's address and login, from the box's inventory copy; the key file is the seal playbook's own.
      read -r host user < <(ansible-inventory -i "$inventory/" --host "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["seal_node"])' "$settings")" |
        python3 -I -c 'import json,sys; v=json.load(sys.stdin); print(v["ansible_host"], v.get("ansible_user", "root"))')
      [[ -n ${host:-} ]] || { echo "openbao-prod: the seal node has no address in the inventory" >&2; exit 1; }
      cmd="cat /var/lib/central-hub/openbao-seal/seal-1.key"
      [[ $user == root ]] || cmd="sudo -n $cmd"
      ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$envdir/known_hosts" \
        -i "$nodekey" "$user@$host" "$cmd" > "$seal_tmp/node.key" || { echo "openbao-prod: could not read the seal key off the seal node" >&2; exit 1; }
      [[ $(wc -c < "$seal_tmp/node.key") -eq 32 ]] || { echo "openbao-prod: the seal node's key is not 32 bytes; nothing kept" >&2; exit 1; }
      if [[ -e $seal_sops ]]; then
        SOPS_AGE_KEY_FILE=$identity "$libexec/sops" decrypt --input-type json --output-type binary \
          --output "$seal_tmp/kept.key" "$seal_sops" || { echo "openbao-prod: $seal_sops does not decrypt with the box's identity" >&2; exit 1; }
        cmp -s "$seal_tmp/kept.key" "$seal_tmp/node.key" || { echo "FAIL: seal-copy: the seal node's key differs from the box's SOPS copy; nothing replaced"; exit 1; }
        echo "PASS: seal-copy: the box's SOPS copy and the seal node's key are the same"
      else
        keep "$seal_tmp/node.key"
        echo "PASS: seal-copy: the seal node's key is kept as the box's SOPS copy, and reads back the same"
      fi
      rm -f -- "$seal_tmp/node.key" "$seal_tmp/kept.key"
    else
      if [[ ! -e $seal_sops ]]; then
        openssl rand -out "$seal_tmp/new.key" 32
        keep "$seal_tmp/new.key"
        rm -f -- "$seal_tmp/new.key"
        echo "openbao-prod: a new prod seal key, kept only as its SOPS copy in the keys folder"
      fi
      SOPS_AGE_KEY_FILE=$identity "$libexec/sops" decrypt --input-type json --output-type binary \
        --output "$seal_tmp/openbao-seal.key" "$seal_sops" || { echo "openbao-prod: $seal_sops does not decrypt with the box's identity" >&2; exit 1; }
      [[ $(wc -c < "$seal_tmp/openbao-seal.key") -eq 32 ]] || { echo "openbao-prod: the seal key in $seal_sops is not 32 bytes" >&2; exit 1; }
      ap playbooks/k8s-openbao-seal.yml -e "openbao_seal_key_file=$seal_tmp/openbao-seal.key"
    fi
    ;;
  l2-policy)
    ap playbooks/k8s.yml --tags lb --limit 'k8s_control_plane[0]'
    ;;
  gitops)
    ap playbooks/k8s-gitops.yml --tags source
    ;;
  admin-firewall-check)
    ap playbooks/k8s-openbao-admin-firewall.yml --check --diff
    ;;
  admin-firewall)
    ap playbooks/k8s-openbao-admin-firewall.yml
    ;;
  ca)
    mkdir -p "$store_keys"
    # kc's arguments reach Ansible's command module as one string, which it splits as a shell would (shlex), so the
    # inner single quotes keep the backslash before the key's dot: kubectl then reads key ca.crt, not ca then crt.
    pem=$(kc -n openbao get secret openbao-tls -o "'jsonpath={.data.ca\.crt}'" | base64 -d) ||
      { echo "openbao-prod: could not read ca.crt of Secret openbao/openbao-tls; nothing written" >&2; exit 1; }
    # Exactly one PEM block, and it a certificate: no second certificate and no other block, such as a key.
    if [[ $(grep -c -- '-----BEGIN ' <<< "$pem") -ne 1 || $(grep -c -- '-----BEGIN CERTIFICATE-----' <<< "$pem") -ne 1 ]] ||
      ! openssl x509 -noout <<< "$pem" 2>/dev/null; then
      echo "openbao-prod: ca.crt of Secret openbao/openbao-tls is not one PEM certificate; nothing written" >&2
      exit 1
    fi
    printf '%s\n' "$pem" > "$store_keys/secrets-store-ca.crt.part"
    mv -- "$store_keys/secrets-store-ca.crt.part" "$store_keys/secrets-store-ca.crt"
    echo "PASS: openbao-prod: ca: the store's CA written to $store_keys/secrets-store-ca.crt ($(openssl x509 -noout -subject -enddate <<< "$pem" | tr '\n' ' '))"
    ;;
  handover)
    mkdir -p "$store_keys"
    [[ -f $store_keys/openbao-admin-role-id ]] || openssl rand -hex 24 | tr -d '\n' > "$store_keys/openbao-admin-role-id"
    [[ -f $store_keys/openbao-admin-secret-id ]] || openssl rand -hex 24 | tr -d '\n' > "$store_keys/openbao-admin-secret-id"
    ap playbooks/k8s-openbao-handover.yml -e "openbao_admin_role_id_file=$store_keys/openbao-admin-role-id" \
      -e "openbao_admin_secret_id_file=$store_keys/openbao-admin-secret-id"
    ;;
  refresh)
    for f in openbao-admin-role-id openbao-admin-secret-id; do
      [[ -s $store_keys/$f ]] || { echo "openbao-prod: $store_keys/$f is missing; run openbao-prod handover first; nothing changed" >&2; exit 1; }
    done
    # With an admin address the play signs in from the box over it (prod's admin is bound to the box), checked against
    # the CA file that `ca` writes.
    if [[ -n $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("admin_address") or "")' "$settings") ]]; then
      [[ -s $store_keys/secrets-store-ca.crt ]] || { echo "openbao-prod: $store_keys/secrets-store-ca.crt is missing; run openbao-prod ca first; nothing changed" >&2; exit 1; }
    fi
    ap playbooks/k8s-openbao-refresh.yml -e openbao_refresh_env=prod -e "openbao_admin_role_id_file=$store_keys/openbao-admin-role-id" \
      -e "openbao_admin_secret_id_file=$store_keys/openbao-admin-secret-id" -e "openbao_refresh_ca_file=$store_keys/secrets-store-ca.crt"
    ;;
  reset-failed-start)
    ns=openbao pod=openbao-0 claim=data-openbao-0
    echo "openbao-prod: before:"
    kc -n "$ns" get "pod/$pod" "pvc/$claim" --no-headers || { echo "openbao-prod: cannot read the pod and its claim; nothing deleted" >&2; exit 1; }
    ready=$(kc -n "$ns" get "pod/$pod" -o 'jsonpath={.status.containerStatuses[0].ready}' 2>/dev/null) || ready=unknown
    [[ $ready == false ]] || { echo "openbao-prod: refused: the pod's ready state is '$ready', not false" >&2; exit 1; }
    logs=$( { kc -n "$ns" logs "$pod" 2>&1; kc -n "$ns" logs "$pod" --previous 2>&1; } || true)
    grep -qF 'self-initialization failed: refusing to unseal' <<< "$logs" ||
      { echo "openbao-prod: refused: the pod's log does not show the self-init failure" >&2; exit 1; }
    # Only a status that parses as JSON and says initialized false lets the delete go on: an unreadable status, a pod that
    # cannot be reached or a store that says true all refuse.
    status=$(kc -n "$ns" exec "$pod" -- bao status -format=json 2>/dev/null) || true
    python3 -I -c 'import json, sys; sys.exit(0 if json.loads(sys.stdin.read()).get("initialized") is False else 1)' <<< "$status" 2>/dev/null ||
      { echo "openbao-prod: refused: bao status does not read as initialized false" >&2; exit 1; }
    echo "openbao-prod: the failed start is confirmed (self-init line in the log, pod not Ready, store not initialized)"
    kc -n "$ns" delete "pod/$pod" --wait=true --timeout=120s
    kc -n "$ns" delete "pvc/$claim" --wait=true --timeout=120s
    echo "openbao-prod: after (the pod and its claim are made again by the StatefulSet):"
    sleep 20
    kc -n "$ns" get "pod/$pod" "pvc/$claim" --no-headers || true
    ;;
  drop-box-path)
    objs="listenersets.gateway.networking.k8s.io/openbao-box tlsroutes.gateway.networking.k8s.io/openbao-box ciliumnetworkpolicies.cilium.io/openbao-box"
    echo "openbao-prod: before:"
    # shellcheck disable=SC2086  # three names, split on purpose
    kc -n openbao get $objs --ignore-not-found --no-headers || true
    app=$(kc -n argocd get application.argoproj.io/openbao-store -o json) || { echo "openbao-prod: cannot read Application openbao-store; nothing deleted" >&2; exit 1; }
    # Argo CD's own word on each of the three: prune (in the cluster, no longer in git), git (still in git: refuse) or absent.
    plan=$(python3 -I -c '
import json, sys
want = {("gateway.networking.k8s.io", "ListenerSet"): "listenersets.gateway.networking.k8s.io",
        ("gateway.networking.k8s.io", "TLSRoute"): "tlsroutes.gateway.networking.k8s.io",
        ("cilium.io", "CiliumNetworkPolicy"): "ciliumnetworkpolicies.cilium.io"}
try:
    res = json.loads(sys.stdin.read())["status"]["resources"]
except Exception as e:
    print("openbao-prod: Application openbao-store has no readable status.resources: %s" % e, file=sys.stderr); sys.exit(1)
seen = {}
for r in res:
    k = (r.get("group", ""), r.get("kind", ""))
    if k in want and r.get("namespace") == "openbao" and r.get("name") == "openbao-box":
        seen[want[k]] = "prune" if r.get("requiresPruning") is True else "git"
for n in want.values(): print(n, seen.get(n, "absent"))
' <<< "$app") || exit 1
    grep -q ' git$' <<< "$plan" && { echo "openbao-prod: refused: Argo CD still has these in git (the drop has not reached prod's sync): $(grep ' git$' <<< "$plan" | cut -d' ' -f1 | tr '\n' ' ')" >&2; exit 1; }
    while read -r name state; do
      if [[ $state == prune ]]; then
        echo "openbao-prod: deleting $name/openbao-box (Argo CD: requiresPruning)"
        kc -n openbao delete "$name/openbao-box" --wait=true --timeout=60s
      else
        echo "openbao-prod: $name/openbao-box: not in Argo CD's status; left alone"
      fi
    done <<< "$plan"
    echo "openbao-prod: after:"
    # shellcheck disable=SC2086
    kc -n openbao get $objs --ignore-not-found --no-headers || true
    ;;
esac
echo "openbao-prod: $action done"
