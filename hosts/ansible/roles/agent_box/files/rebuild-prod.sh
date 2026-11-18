#!/bin/bash
# /usr/local/libexec/agent-box/rebuild-prod.sh: tear prod's Kubernetes layer (c1, VMs 200-249) down and build it
# again from the agent box, with prod's data put back, under D-0035 (docs/runbooks/rebuild-k8s-layer-with-one-command.md,
# "Rebuild prod from the box"). It runs hosts/rebuild-k8s.sh, the same one command as dev, as user `keys` through sudo,
# so the session never sees the Proxmox token, the node key, the seal key, the backup certificates or the inventory.
# Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/rebuild-prod.sh check|rebuild <tap id>|log
# check    read-only. Names every file the run needs that is missing; builds the box's copies of the prod inventory
#          and tfvars and refuses one that still points at the Mac; plans OpenTofu with the Mac's own tfvars on the
#          box's state and needs "no changes" (the box's state is the live prod); lists what a teardown would destroy
#          and refuses anything but node VMs 200-249, VM 258 or 259, or more VMs than the tfvars declare; reaches every
#          prod node with the box's key; checks that neither the box's default route nor its route to the Proxmox
#          API goes through a node VM (D-0035 rule 5); and needs the newest dev run to have passed every stage at this commit
#          (D-0035 rule 3(a)). One PASS or FAIL line each; exit 0 only when every line passes.
# rebuild  <tap id> is the owner's tap on a decision card that names rebuild-prod and this main commit (D-0035
#          rule 3(b), D-0042 rule 6: a delete); it is written to the log. It runs check, then the checks before a
#          teardown (D-0035 rule 5), each of which must pass or nothing is destroyed:
#            1. a backup of every prod node now, and the restore tests on it (k8s-backup.yml --tags drill), so the
#               newest snapshot is minutes old and its restore test passed, each test naming the snapshot it restored
#               into a temporary folder (never over prod's data);
#            2. each node's backup certificate and its key ID on the app, copied off the node into the keys folder,
#               so the rebuilt nodes sign in to the backup as before (k8s_backup_azure_seed_dir);
#            3. the seal key's SOPS copy decrypts and equals the key on the seal node, so the rebuilt store unseals;
#            4. a fresh OPNsense configuration copy, sent off the box (opnsense-backup.sh, opnsense-offbox.sh);
#            5. a fresh secrets bundle, which holds this OpenTofu state, sent off the box (secrets-bundle.sh,
#               secrets-bundle-offbox.sh);
#          then hosts/rebuild-k8s.sh --teardown with prod's stages: the VMs, the cluster, the data disk, the seal
#          key, prod's own newest volume snapshot back onto the empty data disk (k8s-restore.yml), Argo CD and every
#          app, the certificates, sign-in, Keycloak's database back from the same snapshot (k8s-identity-restore.yml),
#          the Argo CD UI, the backup timers on again with the carried certificates, and the checks.
# log      the newest run's lines: the action, the commit, the tap id, the dev run, the stage lines, PASS and FAIL.
# A run's VM IDs must be 200-249; VM 258 (this box) and 259 are refused in any plan. One run at a time, with the
# dev rebuild's lock, so dev and prod never build at once. Only code on main runs with the keys.
set -euo pipefail
umask 077

keys=/etc/agent-keys
pkeys=$keys/prod
work=/var/lib/agent-box
libexec=/usr/local/libexec/agent-box
repo=$work/checkouts/rebuild-prod   # this wrapper's own checkout of central-hub
envdir=$work/rebuild-prod
logs=$envdir/logs
inventory=$envdir/inventory
nodekey=$keys/prod-node-key
tfvars_src=$pkeys/tfvars/k8s.tfvars
tfstate=$pkeys/state/home-k8s.tfstate
tofu_env=$keys/proxmox-lab.env
certs=$pkeys/backup-certs
settings=$work/openbao-prod.json
dev_logs=$work/rebuild-dev/logs
vm_min=200
vm_max=249
export HOME=$work PATH=$libexec/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin
export TF_DATA_DIR=$work/tofu-data/rebuild-prod TF_IN_AUTOMATION=1
export ANSIBLE_COLLECTIONS_PATH=$libexec/collections ANSIBLE_HOME=$work/ansible-home

usage() { echo "usage: rebuild-prod check|rebuild <tap id>|log" >&2; exit 2; }
action=${1:-}
tap=''
case $action in
  check | log) [[ $# -eq 1 ]] || usage ;;
  rebuild)
    [[ $# -eq 2 ]] || usage
    tap=$2
    [[ $tap =~ ^cmsg_[A-Za-z0-9]{20,60}$ ]] || { echo "rebuild-prod: the tap id is the owner's tap message id, cmsg_<letters and digits>" >&2; exit 2; }
    ;;
  *) usage ;;
esac

if [[ $action == log ]]; then
  newest=$(ls -1 "$logs"/run-*.log 2>/dev/null | sort | tail -n 1 || true)
  [[ -n $newest ]] || { echo "rebuild-prod: no run has been logged yet" >&2; exit 1; }
  echo "run: ${newest##*/}"
  sed -E 's/\x1b\[[0-9;]*m//g' -- "$newest" | grep -E '^(rebuild-prod:|rebuild:|[0-9T:-]+Z [a-z-]+ (start|end))|(PASS|FAIL|SKIP):|PLAY RECAP|[^ ]+ +: ok=' | cut -c1-200 | head -n 120 || true
  # The stage lines of the one command's own short log, which names its stages and their results.
  short=$(ls -1 "$envdir"/logs/rebuild-*.log 2>/dev/null | sort | tail -n 1 || true)
  [[ -z $short ]] || { echo "stages: ${short##*/}"; cut -c1-200 -- "$short" | head -n 80; }
  exit 0
fi

mkdir -p "$envdir" "$logs" "$work/state"
chmod 700 "$envdir"

# One rebuild at a time, dev's or prod's, in this wrapper's own checkout of main.
exec 9>"$work/state/rebuild.lock"
flock -n 9 || { echo "rebuild-prod: another rebuild run (dev or prod) is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
commit=$(git -C "$repo" rev-parse HEAD)

stamp=$(date -u +%Y%m%dT%H%M%SZ)
log=$logs/run-$stamp.log
exec > >(tee -a "$log") 2>&1
echo "rebuild-prod: $action at central-hub ${commit:0:12}${tap:+, owner tap $tap}"

fails=0
pass() { echo "PASS: rebuild-prod: $*"; }
fail() { echo "FAIL: rebuild-prod: $*"; fails=$((fails + 1)); }

# --- 1. What the run needs, each named if missing.
need=("$tofu_env" "$tfvars_src" "$tfstate" "$pkeys/inventory-hosts.yml" "$nodekey" "$nodekey.pub"
      "$pkeys/c1-secrets-encryption.key" "$keys/c1-backup.env" "$pkeys/identity.env" "$pkeys/secret-source.env"
      "$pkeys/cloudflare-dns01-token.txt" "$pkeys/openbao-seal.key.sops.json" "$keys/secrets-bundle/age-identity.txt"
      "$settings" "$libexec/ansible-venv/bin/ansible-playbook")
missing=()
for f in "${need[@]}"; do [[ -s $f ]] || missing+=("$f"); done
if (( ${#missing[@]} )); then fail "missing: ${missing[*]}"; else pass "every file the run needs is on the box"; fi
command -v tofu >/dev/null || fail "OpenTofu is not installed; run the agent_box role"

# --- 2. The box's own copies of the tfvars and the inventory.
# The tfvars: the Mac's, with the box's prod node key in place of the Mac's, so the rebuilt nodes take the box's
# logins. Template 9000 and VNet prod stay: the lab token may clone it (agent-access.sh part 2, pick 217).
tfvars=$envdir/k8s.tfvars
if [[ -s $tfvars_src && -s $nodekey.pub ]]; then
  pub=$(cat -- "$nodekey.pub")
  awk -v pub="$pub" '/^[[:space:]]*node_ssh_public_key[[:space:]]*=/ { print "node_ssh_public_key = \"" pub "\""; next } { print }' \
    "$tfvars_src" > "$tfvars"
  if grep -q '^node_ssh_public_key = "ssh-ed25519 ' "$tfvars"; then pass "the box's tfvars copy carries the box's node key"
  else fail "the prod tfvars have no node_ssh_public_key line to set"; fi
  ids=$(grep -Eo '(^|[^_[:alnum:]])vm_id[[:space:]]*=[[:space:]]*[0-9]+' "$tfvars" | grep -Eo '[0-9]+$' || true)
  bad_ids=""
  for id in $ids; do (( id >= vm_min && id <= vm_max )) || bad_ids+=" $id"; done
  if [[ -z $ids ]]; then fail "no vm_id in the prod tfvars"
  elif [[ -n $bad_ids ]]; then fail "node VM IDs outside $vm_min-$vm_max:$bad_ids"
  else pass "node VM IDs ${ids//$'\n'/ } are all in $vm_min-$vm_max"; fi
  nodes_declared=$(wc -w <<< "$ids")
fi

# The inventory: the Mac's, with every ssh login, key and proxy setting and the proxmox group dropped; the box's
# key and plain ssh set; the store's settings (openbao-prod.json) added; the private files pointed at the box's
# copies; the rebuild's own settings set. Any value still pointing at the Mac stops the run, by key name.
rm -rf -- "$inventory"
install -d -m 700 "$inventory"
inv_ok=false
if [[ -s $pkeys/inventory-hosts.yml && -s $settings ]] && python3 -I -c "$(cat <<'PY'
import ipaddress, json, os, sys, yaml
src, dst, key, known, pkeys, keys, certs, settings = sys.argv[1:9]
def die(m):
    print("FAIL: rebuild-prod: " + m); sys.exit(1)
s = json.load(open(settings))
seal, store, cidr = s.get("seal_node") or "", s.get("store_host") or "", s.get("box_cidr") or ""
if not seal or not store: die("openbao-prod.json needs seal_node and store_host")
if cidr:
    try: n = ipaddress.ip_network(cidr, strict=False)
    except ValueError: die("box_cidr must be one address as a /32")
    if n.prefixlen != 32 or n.is_loopback: die("box_cidr must be one address as a /32")
d = yaml.safe_load(open(src))
DROP = {"ansible_ssh_common_args", "ansible_ssh_extra_args", "ansible_ssh_args", "ansible_ssh_private_key_file",
        "ansible_ssh_host", "ansible_ssh_executable", "ansible_connection", "ansible_ssh_pass", "ansible_password",
        "ansible_private_key_file", "ansible_host_key_checking", "k8s_gateway_smoke_client", "k8s_certs_smoke_client",
        "k8s_gitops_source_openbao_address", "k8s_gitops_source_openbao_ca_file", "k8s_gitops_source_openbao_measure",
        "k8s_gitops_source_openbao_in_cluster", "k8s_gitops_source_openbao_seal_node", "k8s_gitops_source_openbao_box_cidr",
        "k8s_gitops_source_openbao_store_host", "k8s_backup_azure_fixed_cert_file"}
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
w = find(d, "k8s_workers")
workers = list(((w or {}).get("hosts") or {}))
if not workers: die("the prod inventory has no k8s_workers host")
names = set()
def hosts(n):
    if isinstance(n, dict):
        for k, v in n.items():
            if k == "hosts" and isinstance(v, dict): names.update(v)
            else: hosts(v)
hosts(g)
if seal not in names: die("seal_node is not a k8s_nodes host of the prod inventory")
v = g.setdefault("vars", {})
# The private files the Mac's inventory names, each at the box's copy (prod_files.yml and the keys wrapper).
MAP = {"k8s_control_plane_encryption_key_file": pkeys + "/c1-secrets-encryption.key",
       "k8s_backup_env_file": keys + "/c1-backup.env",
       "k8s_certs_cloudflare_token_file": pkeys + "/cloudflare-dns01-token.txt",
       "k8s_identity_values_file": pkeys + "/identity.env",
       "k8s_certs_lab_ca_cert_file": pkeys + "/lab-ca/c1-intermediate-chain.crt",
       "k8s_certs_lab_ca_key_file": pkeys + "/lab-ca/c1-intermediate.key",
       "k8s_identity_theme_dir": pkeys + "/identity-theme"}
def remap(n):
    if isinstance(n, dict):
        for k in list(n):
            if k in MAP and isinstance(n[k], str) and n[k]: n[k] = MAP[k]
            else: remap(n[k])
    elif isinstance(n, list):
        for i in n: remap(i)
remap(d)
v["ansible_ssh_private_key_file"] = key
v["ansible_ssh_common_args"] = "-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=" + known
v["k8s_gateway_smoke_client"] = "localhost"
v["k8s_certs_smoke_client"] = "localhost"
v["k8s_gitops_source_openbao_in_cluster"] = True
v["k8s_gitops_source_openbao_seal_node"] = seal
v["k8s_gitops_source_openbao_store_host"] = store
if cidr: v["k8s_gitops_source_openbao_box_cidr"] = cidr
# The rebuild's own: prod's own snapshot back (k8s-restore.yml, k8s-identity-restore.yml), onto stable folder names
# so the new claims find the restored folders, the backup certificates carried over, and no throwaway identity copy.
v["k8s_backup_restore_own_env"] = True
v["k8s_backup_restore_source_host"] = workers[0]
v["k8s_gitops_source_local_path_stable_folders"] = True
v["k8s_backup_azure_seed_dir"] = certs
v["k8s_backup_restore_check_identity"] = False
yaml.safe_dump(d, open(dst, "w"), default_flow_style=False)
PY
)" "$pkeys/inventory-hosts.yml" "$inventory/hosts.yml" "$nodekey" "$envdir/known_hosts" "$pkeys" "$keys" "$certs" "$settings"; then
  chmod 600 "$inventory/hosts.yml"
  # Every k8s_nodes host as Ansible sees it: plain ssh with the box's key, labelled env prod, at an address, and no
  # value that still names a file on the Mac. The names of the mapped files must exist on the box.
  if ansible-inventory -i "$inventory/" --list | python3 -I -c "$(cat <<'PY'
import json, os, re, sys
nodekey, known = sys.argv[1:3]
inv = json.load(sys.stdin)
hv = inv.get("_meta", {}).get("hostvars", {})
def members(g, seen=None):
    seen = seen or set()
    out = set(inv.get(g, {}).get("hosts", []))
    for c in inv.get(g, {}).get("children", []):
        if c not in seen:
            seen.add(c); out |= members(c, seen)
    return out
nodes = members("k8s_nodes")
bad = []
if not nodes: bad.append("the prod inventory lists no k8s_nodes hosts")
want = "-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=" + known
mac = re.compile(r"^(~|/Users/|/home/[^/]+/\.config/)|/\.config/central-hub(/|$)")
for h in sorted(nodes):
    v = hv.get(h, {})
    if not v.get("ansible_host"): bad.append("host %s has no ansible_host" % h)
    if v.get("ansible_connection", "ssh") != "ssh": bad.append("host %s uses a connection other than ssh" % h)
    if v.get("ansible_ssh_common_args") != want or v.get("ansible_ssh_private_key_file") != nodekey:
        bad.append("host %s has ssh arguments or a key other than the box's own" % h)
    env = (v.get("k8s_gitops_cluster_labels") or {}).get("env")
    if env != "prod": bad.append("host %s is labelled env %s, not prod" % (h, env))
    for k, val in v.items():
        if isinstance(val, str) and mac.search(val): bad.append("host %s: %s still points at the Mac" % (h, k))
    for k in ("k8s_control_plane_encryption_key_file", "k8s_backup_env_file", "k8s_certs_cloudflare_token_file",
              "k8s_identity_values_file", "k8s_certs_lab_ca_cert_file", "k8s_certs_lab_ca_key_file", "k8s_identity_theme_dir"):
        p = v.get(k)
        if isinstance(p, str) and p and not os.path.exists(p): bad.append("%s is %s, which is not on the box" % (k, p))
for b in sorted(set(bad)): print("FAIL: rebuild-prod: inventory: " + b)
if bad: sys.exit(1)
print("PASS: rebuild-prod: %d prod nodes, plain ssh with the box's key, every private file at the box's copy" % len(nodes))
PY
)" "$nodekey" "$envdir/known_hosts"; then inv_ok=true; else fails=$((fails + 1)); fi
else
  fails=$((fails + 1))
fi

# --- 3. OpenTofu: the box's state is the live prod, and the teardown would destroy only prod's node VMs.
tf=$repo/hosts/terraform/home/k8s
# shellcheck source=/dev/null
tofu_k8s() { (set -a; . "$tofu_env"; set +a; tofu -chdir="$tf" "$@"); }
if [[ -s $tofu_env && -s $tfstate && -s $tfvars_src ]] && command -v tofu >/dev/null; then
  if tofu_k8s init -input=false -reconfigure -backend-config="path=$tfstate" > "$envdir/tofu-init.out" 2>&1; then
    rc=0; tofu_k8s plan -input=false -lock=false -detailed-exitcode -var-file="$tfvars_src" > "$envdir/tofu-plan.out" 2>&1 || rc=$?
    case $rc in
      0) pass "OpenTofu: no changes with the Mac's tfvars, so the box's state is the live prod" ;;
      2) fail "OpenTofu plans changes with the Mac's tfvars: the box's state or tfvars differ from the live prod; copy the controller's files again" ;;
      *) fail "OpenTofu plan failed (rc $rc): $(grep -m1 -E 'Error' "$envdir/tofu-plan.out" | cut -c1-160)" ;;
    esac
    rc=0; tofu_k8s plan -input=false -lock=false -destroy -var-file="$tfvars_src" -out="$envdir/destroy.plan" > "$envdir/tofu-destroy.out" 2>&1 || rc=$?
    if [[ $rc -eq 0 ]] && tofu_k8s show -json "$envdir/destroy.plan" > "$envdir/destroy.json" 2>/dev/null; then
      if out=$(python3 -I -c "$(cat <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
lo, hi, cap = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
ids, bad = [], []
for rc in plan.get("resource_changes", []):
    if "delete" not in rc.get("change", {}).get("actions", []): continue
    t = rc.get("type")
    vm = (rc.get("change", {}).get("before") or {}).get("vm_id")
    if t != "proxmox_virtual_environment_vm": bad.append("%s %s" % (t, rc.get("address"))); continue
    if not isinstance(vm, int) or not (lo <= vm <= hi) or vm in (258, 259): bad.append("VM %s" % vm); continue
    ids.append(vm)
if bad: print("would destroy something other than prod's node VMs: " + ", ".join(bad)); sys.exit(1)
if not ids: print("would destroy nothing: the state holds no prod node VM"); sys.exit(1)
if len(ids) > cap: print("would destroy %d VMs, more than the %d the tfvars declare" % (len(ids), cap)); sys.exit(1)
print("a teardown destroys only VMs " + " ".join(str(i) for i in sorted(ids)))
PY
)" "$envdir/destroy.json" "$vm_min" "$vm_max" "${nodes_declared:-0}"); then pass "$out"; else fail "$out"; fi
    else
      fail "OpenTofu could not plan the teardown (rc $rc): $(grep -m1 -E 'Error' "$envdir/tofu-destroy.out" | cut -c1-160)"
    fi
    rm -f -- "$envdir/destroy.plan" "$envdir/destroy.json"
  else
    fail "OpenTofu init failed: $(grep -m1 -E 'Error' "$envdir/tofu-init.out" | cut -c1-160)"
  fi
fi

# --- 4. The box reaches every prod node now, with its key (the checks below and the teardown's preconditions do).
old_known=$envdir/known_hosts.old
ssh_node() { # host user command...
  local host=$1 user=$2; shift 2
  ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$old_known" \
    -i "$nodekey" "$user@$host" "$@"
}
node_list=$envdir/nodes.txt
: > "$node_list"
if [[ $inv_ok == true ]]; then
  ansible-inventory -i "$inventory/" --list | python3 -I -c '
import json, sys
inv = json.load(sys.stdin); hv = inv["_meta"]["hostvars"]
def members(g):
    out = set(inv.get(g, {}).get("hosts", []))
    for c in inv.get(g, {}).get("children", []): out |= members(c)
    return out
for h in sorted(members("k8s_nodes")): print(h, hv[h]["ansible_host"], hv[h].get("ansible_user", "root"))' > "$node_list"
  reached=0 total=0
  while read -r name host user; do
    total=$((total + 1))
    if ssh_node "$host" "$user" true </dev/null >/dev/null 2>&1; then reached=$((reached + 1)); else fail "no ssh login to node $name with the box's key"; fi
  done < "$node_list"
  [[ $total -gt 0 && $reached -eq $total ]] && pass "the box's key reaches all $total prod nodes"
fi

# --- 4b. The box's route (D-0035 rule 5): neither its default route nor its route to the Proxmox API may go
# through a node the teardown destroys, or the run would cut itself off half way. Only the routing table is read.
if [[ $inv_ok == true && -s $tofu_env && -s $node_list ]]; then
  node_ips=" "
  while read -r _ host _; do
    [[ $host =~ ^[0-9.]+$ ]] && node_ips+="$host "
    for a in $(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u); do node_ips+="$a "; done
  done < "$node_list"
  api_host=$(sed -n 's|^PROXMOX_VE_ENDPOINT=https\{0,1\}://\([^:/]*\).*|\1|p' "$tofu_env" | head -n 1)
  api_ip=$(getent ahostsv4 "$api_host" 2>/dev/null | awk 'NR == 1 {print $1}' || true)
  hop() { sed -n 's/.* via \([0-9.]*\).*/\1/p' <<< "$1" | head -n 1; }
  api_route=$( [[ -n $api_ip ]] && ip -4 route get "$api_ip" 2>/dev/null | head -n 1 || true)
  api_hop=$(hop "$api_route"); api_hop=${api_hop:-$api_ip}
  def_hop=$(hop " $(ip -4 route show default 2>/dev/null | head -n 1)")
  if [[ -z $api_ip || -z $api_route ]]; then fail "the box has no route to the Proxmox API's address ($api_host)"
  elif [[ -z $def_hop ]]; then fail "the box has no default route"
  elif [[ $node_ips == *" $api_ip "* || $node_ips == *" $api_hop "* || $node_ips == *" $def_hop "* ]]; then
    fail "the box's route goes through a prod node the teardown destroys (Proxmox API next hop $api_hop, default via $def_hop)"
  else pass "the box's routes do not go through a prod node: Proxmox API next hop $api_hop, default via $def_hop"; fi
fi

# --- 5. Dev first (D-0035 rule 3(a)): the newest dev run passed every stage at this same commit.
dev_short=$(ls -1 "$dev_logs"/rebuild-*.log 2>/dev/null | sort | tail -n 1 || true)
if [[ -z $dev_short ]]; then fail "no dev run is logged on the box"
elif ! grep -qx 'rebuild: all stages passed' "$dev_short"; then fail "the newest dev run (${dev_short##*/}) did not pass every stage"
elif ! grep -qx "rebuild: central-hub $commit" "$dev_short"; then fail "the newest dev run (${dev_short##*/}) ran another commit than ${commit:0:12}; run dev again first"
else pass "dev passed every stage at ${commit:0:12} (run ${dev_short##*/})"; dev_run=${dev_short##*/}; fi

if [[ $fails -gt 0 ]]; then echo "rebuild-prod: $action: $fails checks failed; nothing was changed"; exit 1; fi
if [[ $action == check ]]; then echo "rebuild-prod: check: every check passed; nothing was changed"; exit 0; fi

# ===== rebuild: the checks before a teardown (D-0035 rule 5). Any failure stops the run before anything is destroyed.
echo "rebuild-prod: rebuild of prod at ${commit:0:12}, owner tap $tap, after dev run $dev_run"
ap() { (cd "$repo/hosts/ansible" && ansible-playbook -i "$inventory/" "$@"); }
old_args="ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$old_known'"

# 1. A backup of every node now, then the restore tests on it.
# The restore tests restore into a temporary folder on each node, never over its data. The first worker's
# volume test and the control plane's etcd test must each name the snapshot they restored: a node with no
# volume record passes with nothing to test, and that is not a backup of prod's data.
drill_out=$envdir/drill-$stamp.log
ap playbooks/k8s-backup.yml --tags drill -e k8s_backup_drill=true -e "$old_args" | tee "$drill_out" ||
  { echo "FAIL: rebuild-prod: the backup and restore test before the teardown failed; nothing was destroyed"; exit 1; }
vol_pass=$(grep -oE 'PASS: volume restore test, [1-9][0-9]* folders, [0-9]+ database dumps, snapshot [0-9a-f]{8} of [0-9T:-]+' "$drill_out" | head -n 1 || true)
etcd_pass=$(grep -oE 'PASS: etcd restore test, revision [0-9]+, [0-9]+ keys under /, key [^,]+ present, snapshot [0-9a-f]{8} of [0-9T:-]+' "$drill_out" | head -n 1 || true)
if [[ -z $vol_pass || -z $etcd_pass ]]; then
  echo "FAIL: rebuild-prod: the drill named no tested volume snapshot or no tested etcd snapshot; nothing was destroyed"; exit 1
fi
echo "PASS: rebuild-prod: every prod node backed up now, and its restore test passed: ${vol_pass#PASS: }; ${etcd_pass#PASS: }"

# 2. Each node's backup certificate and key ID, kept in the keys folder; never printed.
install -d -m 700 "$certs"
while read -r name host user; do
  sudo_=""; [[ $user == root ]] || sudo_="sudo -n "
  for ext in pem pem.keyid; do
    ssh_node "$host" "$user" "${sudo_}cat /etc/central-hub/azure/backup.$ext" > "$certs/$name.$ext.part" </dev/null ||
      { rm -f -- "$certs/$name.$ext.part"; echo "FAIL: rebuild-prod: could not read node $name's backup certificate ($ext); nothing was destroyed"; exit 1; }
  done
  grep -q -- '-----BEGIN CERTIFICATE-----' "$certs/$name.pem.part" && grep -q -- 'PRIVATE KEY-----' "$certs/$name.pem.part" &&
    [[ -s $certs/$name.pem.keyid.part ]] ||
    { rm -f -- "$certs/$name".*.part; echo "FAIL: rebuild-prod: node $name's backup certificate or key ID is not whole; nothing was destroyed"; exit 1; }
  mv -- "$certs/$name.pem.part" "$certs/$name.pem"; mv -- "$certs/$name.pem.keyid.part" "$certs/$name.pem.keyid"
  chmod 600 "$certs/$name.pem" "$certs/$name.pem.keyid"
done < "$node_list"
echo "PASS: rebuild-prod: each node's backup certificate kept for its rebuilt node"

# 3. The seal key: its SOPS copy decrypts to the 32 bytes on the seal node, and stays in memory only for this run.
identity=$keys/secrets-bundle/age-identity.txt
seal_sops=$pkeys/openbao-seal.key.sops.json
find /dev/shm -maxdepth 1 -name 'rebuild-prod-seal.*' -user "$(id -u)" -exec rm -rf -- {} +
seal_tmp=$(mktemp -d /dev/shm/rebuild-prod-seal.XXXXXX)
trap 'rm -rf -- "$seal_tmp"' EXIT
trap 'exit 1' INT TERM HUP
SOPS_AGE_KEY_FILE=$identity "$libexec/sops" decrypt --input-type json --output-type binary --output "$seal_tmp/openbao-seal.key" "$seal_sops" ||
  { echo "FAIL: rebuild-prod: $seal_sops does not decrypt with the box's identity; nothing was destroyed"; exit 1; }
[[ $(wc -c < "$seal_tmp/openbao-seal.key") -eq 32 ]] || { echo "FAIL: rebuild-prod: the seal key's SOPS copy is not 32 bytes; nothing was destroyed"; exit 1; }
seal_node=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["seal_node"])' "$settings")
read -r _ seal_host seal_user < <(awk -v n="$seal_node" '$1 == n' "$node_list")
[[ -n ${seal_host:-} ]] || { echo "FAIL: rebuild-prod: the seal node is not among the prod nodes; nothing was destroyed"; exit 1; }
sudo_=""; [[ $seal_user == root ]] || sudo_="sudo -n "
ssh_node "$seal_host" "$seal_user" "${sudo_}cat /var/lib/central-hub/openbao-seal/seal-1.key" > "$seal_tmp/node.key" </dev/null ||
  { echo "FAIL: rebuild-prod: could not read the seal key on the seal node; nothing was destroyed"; exit 1; }
cmp -s "$seal_tmp/node.key" "$seal_tmp/openbao-seal.key" ||
  { echo "FAIL: rebuild-prod: the seal key's SOPS copy differs from the seal node's key (run openbao-prod seal-copy); nothing was destroyed"; exit 1; }
rm -f -- "$seal_tmp/node.key"
echo "PASS: rebuild-prod: the seal key's SOPS copy equals the seal node's key"

# 4 and 5. The firewall's configuration and the secrets bundle (with this state file), fresh and off the box.
for job in opnsense-backup opnsense-offbox secrets-bundle secrets-bundle-offbox; do
  "$libexec/$job.sh" || { echo "FAIL: rebuild-prod: $job failed; nothing was destroyed"; exit 1; }
done
echo "PASS: rebuild-prod: the OPNsense configuration and the secrets bundle with this state are fresh and off the box"

# The secrets store's rebuild hold, as dev's: with snapshots of the store on the box, the rebuilt store waits for
# restore-rebuilt (the owner's tap) or clear-hold before any new snapshot replaces them.
if compgen -G "$pkeys/openbao-snapshots/raft-*.snap" >/dev/null; then
  [[ -e $work/state/secrets-store-prod.rebuilding ]] || date -u +%FT%TZ > "$work/state/secrets-store-prod.rebuilding"
  echo "rebuild-prod: the secrets store's rebuild hold is set; after the run, restore-rebuilt (the owner's tap) or clear-hold"
fi

# From here prod's cluster is built with stable folder names, which the box's other prod copies follow (openbao-prod).
date -u +%FT%TZ > "$work/state/prod-stable-folders"
# The rebuilt nodes have new host keys: the build starts with no known hosts.
rm -f -- "$envdir/known_hosts"

stages="vms cluster storage openbao-seal restore gitops secrets apps gateway certs identity identity-db ui backup checks"
cat > "$envdir/rebuild.env" <<ENV
ENV_NAME=prod
VM_ID_MIN=$vm_min
VM_ID_MAX=$vm_max
TFVARS=$tfvars
TFSTATE=$tfstate
TOFU_ENV=$tofu_env
INVENTORY=$inventory/
STAGES="$stages"
SECRET_SOURCE_FILE=$pkeys/secret-source.env
OPENBAO_SEAL_KEY_FILE=$seal_tmp/openbao-seal.key
RESTORE_HOOK='cd "\$REPO/hosts/ansible" && ansible-playbook -i "\$INVENTORY" playbooks/k8s-restore.yml -e k8s_backup_enabled=false'
RESTORE_CHECK_HOOK='cd "\$REPO/hosts/ansible" && ansible-playbook -i "\$INVENTORY" playbooks/k8s-restore.yml --tags restore_check -e k8s_backup_enabled=false'
ENV
chmod 600 "$envdir/rebuild.env"
echo "rebuild-prod: teardown and build start: $stages"
rc=0
bash "$repo/hosts/rebuild-k8s.sh" "$envdir" --teardown || rc=$?
if [[ $rc -eq 0 ]]; then echo "PASS: rebuild-prod: prod torn down and built again at ${commit:0:12}, data back, backups on"
else echo "FAIL: rebuild-prod: the one command stopped (rc $rc); rebuild-prod log names the stage"; fi
exit "$rc"
