#!/bin/bash
# /usr/local/libexec/agent-box/rebuild-prod.sh: tear prod's Kubernetes layer (c1, VMs 200-249) down and build it
# again from the agent box, with prod's data put back, under D-0035 (docs/runbooks/rebuild-k8s-layer-with-one-command.md,
# "Rebuild prod from the box"). It runs hosts/rebuild-k8s.sh, the same one command as dev, as user `keys` through sudo,
# so the session never sees the Proxmox token, the node key, the seal key, the backup certificates or the inventory.
# Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/rebuild-prod.sh check|rebuild <tap id> <commit>|log
# check    read-only, at main's newest commit. Names every file the run needs that is missing; builds the box's copies of the prod inventory
#          and tfvars and refuses one that still points at the Mac; plans OpenTofu with the Mac's own tfvars on the
#          box's state and needs "no changes" (the box's state is the live prod); lists what a teardown would destroy
#          and refuses anything but node VMs 200-249, VM 258 or 259, or more VMs than the tfvars declare; reaches every
#          prod node with the box's key; checks that neither the box's default route nor its route to the Proxmox
#          API goes through a node VM (D-0035 rule 5); and needs the newest dev run to have passed every stage at this commit
#          (D-0035 rule 3(a)). One PASS or FAIL line each; exit 0 only when every line passes.
# rebuild  <tap id> is the owner's go that names rebuild-prod and <commit> (D-0035 rule 3(b), D-0042 rule 6: a delete);
#          it is written to the log. <commit> (7 to 40 hex digits) must be on main; the run builds that commit, not
#          main's newest, so a merge after the dev run and the go neither moves the code under the go nor forces dev
#          again. It runs check at that commit, then the checks before a teardown (D-0035 rule 5), each of which must
#          pass or nothing is destroyed:
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
#          The volume snapshot the restore brings back is always pinned: the snapshot the drill backed up and tested before
#          the teardown (or the one named by the optional <volume snapshot id>), never "latest". Once the teardown starts,
#          the box keeps the pin (<state>/prod-restore-pin) until a run ends well. A run that finds the last rebuild
#          stopped after its teardown (prod's nodes rebuilt and empty) takes no backup, because that would snapshot empty
#          nodes and the repository's retention (daily, weekly, monthly: the newest of a day wins) would forget the good
#          snapshot: it needs the pin (kept, or given as the fourth argument) and refuses without it, before anything
#          is backed up or destroyed.
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
sftp_keys=$pkeys/backup-sftp
settings=$work/openbao-prod.json
dev_logs=$work/rebuild-dev/logs
vm_min=200
vm_max=249
export HOME=$work PATH=$libexec/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export TF_DATA_DIR=$work/tofu-data/rebuild-prod TF_IN_AUTOMATION=1
export ANSIBLE_COLLECTIONS_PATH=$libexec/collections ANSIBLE_HOME=$work/ansible-home

usage() { echo "usage: rebuild-prod check|rebuild <tap id> <commit> [<volume snapshot id>]|log" >&2; exit 2; }
action=${1:-}
tap=''
want=''
given_pin=''
case $action in
  check | log) [[ $# -eq 1 ]] || usage ;;
  rebuild)
    [[ $# -eq 3 || $# -eq 4 ]] || usage
    tap=$2 want=$3 given_pin=${4:-}
    [[ -z $given_pin || $given_pin =~ ^[0-9a-f]{64}$ ]] || { echo "rebuild-prod: the volume snapshot ID is the full restic ID, 64 hex digits" >&2; exit 2; }
    [[ $tap =~ ^cmsg_[A-Za-z0-9]{20,60}$ ]] || { echo "rebuild-prod: the tap id is the owner's tap message id, cmsg_<letters and digits>" >&2; exit 2; }
    [[ $want =~ ^[0-9a-f]{7,40}$ ]] || { echo "rebuild-prod: the commit is the one the owner's go names, 7 to 40 hex digits" >&2; exit 2; }
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

# The oldest commit a go may name: main's merge of #624, the same floor as the dev wrapper's (rebuild.sh). The run uses
# that commit's own hosts/rebuild-k8s.sh, and one below it leaves dev up after a full run that had memory to spare
# (below #624), lacks the refusal while VM 256 exists (below #573) and the memory preflight (below #343). Raise it with
# rebuild.sh's whenever rebuild-k8s.sh gains a refusal or an end step every run must keep. Since #748 (24ed84e) it is
# the commit whose teardown stage runs TEARDOWN_HOOK, as in rebuild.sh.
PIN_FLOOR=24ed84e6dc0810fb00bc5fe35a3884e91b723b39

# One rebuild at a time, dev's or prod's, in this wrapper's own checkout of main.
exec 9>"$work/state/rebuild.lock"
flock -n 9 || { echo "rebuild-prod: another rebuild run (dev or prod) is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
if [[ -n $want ]]; then
  # The commit the go names, and only if it is on main: never a branch, never a commit main does not hold.
  pinned=$(git -C "$repo" rev-parse --quiet --verify "$want^{commit}" 2>/dev/null) ||
    { echo "rebuild-prod: commit $want is not in the box's checkout of main" >&2; exit 1; }
  git -C "$repo" merge-base --is-ancestor "$pinned" origin/main ||
    { echo "rebuild-prod: commit $want is not on main" >&2; exit 1; }
  git -C "$repo" merge-base --is-ancestor "$PIN_FLOOR" "$pinned" ||
    { echo "rebuild-prod: commit $want is older than the floor ${PIN_FLOOR:0:7}, whose rebuild-k8s.sh has the refusals and the teardown a run must keep" >&2; exit 1; }
  git -C "$repo" checkout --quiet --detach "$pinned"
else
  git -C "$repo" checkout --quiet --detach origin/main
fi
commit=$(git -C "$repo" rev-parse HEAD)

stamp=$(date -u +%Y%m%dT%H%M%SZ)
log=$logs/run-$stamp.log
exec > >(tee -a "$log") 2>&1
echo "rebuild-prod: $action at central-hub ${commit:0:12}${tap:+, owner tap $tap}"

# --- 0. The restore pin, and whether the last rebuild stopped after its teardown (prod's nodes rebuilt and empty).
pin_file=$work/state/prod-restore-pin
pin=$(head -n 1 -- "$pin_file" 2>/dev/null || true)
torn=''
if [[ $action == rebuild ]]; then
  prev=''
  while IFS= read -r f; do
    [[ $f == "$log" ]] && continue
    # The newest run that reached its teardown decides. A later run that stopped before it (prod run 5, on the empty nodes' sftp keys)
    # destroyed nothing and says nothing about the state the teardown left.
    if grep -q '^rebuild-prod: teardown and build start' -- "$f"; then prev=$f; break; fi
  done < <(ls -1r "$logs"/run-*.log 2>/dev/null || true)
  if [[ -n $prev ]] && grep -q '^rebuild-prod: teardown and build start' -- "$prev" &&
     ! grep -q '^PASS: rebuild-prod: prod torn down and built again' -- "$prev"; then torn=${prev##*/}; fi
  if [[ -n $given_pin && -z $torn ]]; then
    echo "FAIL: rebuild-prod: a volume snapshot ID is only for a run after one that stopped after its teardown; the last rebuild run did not, so prod holds live data and the drill takes a new backup first. Nothing was backed up or destroyed."; exit 1
  fi
  if [[ -z $torn && -n $pin ]]; then echo "rebuild-prod: ignoring a restore pin left in the box's state: no run stopped after its teardown, so nothing was rebuilt empty"; pin=''; fi
  # The snapshot the torn run's own drill tested and backed up before its teardown, from its log (a pin file may be missing: a run from before
  # the pin existed leaves none). A snapshot ID given with no pin file must start with it: an older snapshot of the same host would
  # otherwise restore stale data.
  if [[ -n $torn && -z $pin && -n $given_pin ]]; then
    tested=$(sed -nE 's/^PASS: rebuild-prod: every prod node backed up now, and its restore test passed: volume restore test, [^;]*snapshot ([0-9a-f]{8}) of .*/\1/p; s/^PASS: rebuild-prod: restore snapshot ([0-9a-f]{12}) is pinned.*/\1/p' -- "$logs/$torn" | head -n 1)
    if [[ -z $tested ]]; then
      echo "FAIL: rebuild-prod: the box holds no restore pin and the log of the stopped run ($torn) names no tested volume snapshot, so the ID given cannot be checked against it; nothing was backed up or destroyed"; exit 1
    fi
    if [[ $given_pin != "$tested"* ]]; then
      echo "FAIL: rebuild-prod: the snapshot ID given ($given_pin) is not the snapshot the stopped run ($torn) backed up and tested before its teardown ($tested...); nothing was backed up or destroyed"; exit 1
    fi
  fi
  if [[ -n $given_pin ]]; then
    if [[ -n $pin && $given_pin != "$pin"* ]]; then
      echo "FAIL: rebuild-prod: the box holds the restore pin $pin, and the snapshot ID given is $given_pin, which is another snapshot; nothing was backed up or destroyed"; exit 1
    fi
    pin=$given_pin
  fi
  if [[ -n $torn && -z $pin ]]; then
    echo "FAIL: rebuild-prod: the last rebuild run ($torn) stopped after its teardown, so prod's nodes are rebuilt and empty, and a backup now would snapshot them and let the repository forget the good one. Give the full ID of the volume snapshot to restore as the fourth argument: rebuild <tap id> <commit> <volume snapshot id>. Nothing was backed up or destroyed."; exit 1
  fi
  if [[ -n $torn ]]; then
    # The nodes are the rebuilt ones: their host keys are new, and the old ones the pre-teardown steps pinned no longer match.
    rm -f -- "$envdir/known_hosts.old" "$work/c1-ansible/known_hosts"
  fi
fi

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
# The two off-box send scripts the pre-teardown steps run must be the copies of the commit the box last applied: the role writes
# backend-files.sha256 from its own files, so an old, missing or hand-edited script differs from it (the first prod run stopped at step 4
# because the box still had an old opnsense-offbox.sh and no secrets-bundle-offbox.sh).
man=$libexec/backend-files.sha256
if [[ ! -s $man ]]; then
  fail "$man is missing: the installed off-box scripts cannot be compared with the repo (run the agent_box role)"
else
  n=0; badn=0
  while read -r want name extra; do
    [[ -n $want && -n $name && -z ${extra:-} && $name != */* ]] || { badn=$((badn + 1)); continue; }
    n=$((n + 1))
    have=$(sha256sum -- "$libexec/$name" 2>/dev/null | cut -d' ' -f1) || have=
    [[ -n $have && $have == "$want" ]] || { fail "$name is missing or differs from the box's baseline copy (installed ${have:0:12}, expected ${want:0:12})"; badn=$((badn + 1)); }
  done < "$man"
  if (( badn == 0 && n > 0 )); then pass "the $n off-box script(s) match the box's baseline copies"; elif (( n == 0 )); then fail "$man lists no script"; fi
fi

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
rm -rf -- "$inventory" "$envdir/backup-mode"
install -d -m 700 "$inventory"
inv_ok=false
if [[ -s $pkeys/inventory-hosts.yml && -s $settings ]] && python3 -I -c "$(cat <<'PY'
import ipaddress, json, os, sys, yaml
src, dst, key, known, pkeys, keys, certs, settings, repo, sftp_keys = sys.argv[1:11]
def die(m):
    print("FAIL: rebuild-prod: " + m); sys.exit(1)
s = json.load(open(settings))
seal, store, cidr = s.get("seal_node") or "", s.get("store_host") or "", s.get("box_cidr") or ""
if not seal or not store: die("openbao-prod.json needs seal_node and store_host")
if cidr:
    try: n = ipaddress.ip_network(cidr, strict=False)
    except ValueError: die("box_cidr must be one address as a /32")
    if n.prefixlen != 32 or n.is_loopback: die("box_cidr must be one address as a /32")
admin = s.get("admin_address") or ""
if admin:
    try: a = ipaddress.ip_address(admin)
    except ValueError: a = None
    if a is None or a.version != 4 or a.is_loopback: die("admin_address must be one IPv4 address, not loopback")
    if not cidr: die("admin_address needs box_cidr: only the box's /32 may reach the admin address")
d = yaml.safe_load(open(src))
# The Proxmox host's address on VNet mgmt (proxmox_host_mgmt_address, on the proxmox group or its hosts) is read before the group
# is dropped, so the nodes' sftp alias can name the host with no proxmox group in the box's copy. Only that one address passes,
# as a variable on k8s_nodes; the group's logins and keys do not reach the box. Nothing is printed.
def pve_address(n):
    if isinstance(n, dict):
        p = n.get("proxmox")
        if isinstance(p, dict) and ("hosts" in p or "children" in p or "vars" in p):
            for part in [p.get("vars")] + list((p.get("hosts") or {}).values()):
                a = (part or {}).get("proxmox_host_mgmt_address") if isinstance(part, dict) else None
                if isinstance(a, str) and a: return a
            return ""
        for x in n.values():
            r = pve_address(x)
            if r: return r
    elif isinstance(n, list):
        for x in n:
            r = pve_address(x)
            if r: return r
    return ""
pve_addr = pve_address(d)
DROP = {"ansible_ssh_common_args", "ansible_ssh_extra_args", "ansible_ssh_args", "ansible_ssh_private_key_file",
        "ansible_ssh_host", "ansible_ssh_executable", "ansible_connection", "ansible_ssh_pass", "ansible_password",
        "ansible_private_key_file", "ansible_host_key_checking", "k8s_gateway_smoke_client", "k8s_certs_smoke_client",
        "k8s_gitops_source_openbao_address", "k8s_gitops_source_openbao_ca_file", "k8s_gitops_source_openbao_measure",
        "k8s_gitops_source_openbao_in_cluster", "k8s_gitops_source_openbao_seal_node", "k8s_gitops_source_openbao_box_cidr",
        "k8s_gitops_source_openbao_store_host", "k8s_gitops_source_openbao_admin_address", "k8s_gitops_source_notebook_runner", "k8s_backup_azure_fixed_cert_file"}
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
       "k8s_gitops_sso_root_ca_file": pkeys + "/lab-ca/root.crt"}
# The sign-in theme folder keeps its own name under <pkeys>/identity-theme/, where the controller's prod-files run copies it
# (tasks/prod_files.yml) and c1-ansible.sh looks: the folder's name is the theme's name in Keycloak (k8s_identity vars).
def remap(n):
    if isinstance(n, dict):
        for k in list(n):
            if k in MAP and isinstance(n[k], str) and n[k]: n[k] = MAP[k]
            elif k == "k8s_identity_theme_dir" and isinstance(n[k], str) and n[k].strip("/"):
                n[k] = pkeys + "/identity-theme/" + n[k].rstrip("/").rsplit("/", 1)[-1]
            else: remap(n[k])
    elif isinstance(n, list):
        for i in n: remap(i)
remap(d)
# The plays that restore prod (k8s-restore.yml, k8s-identity-restore.yml) read k8s_gitops_cluster_labels.env in their
# pre_tasks, where the k8s_gitops role's default (env prod) is not loaded. The Mac's inventory leaves the labels to that
# default, so with no labels set anywhere the box's copy gets the role's own default labels, which say prod. Labels set
# anywhere in the inventory are left as they are, and the check below still refuses one whose env is not prod.
def has_key(n, name):
    if isinstance(n, dict): return name in n or any(has_key(x, name) for x in n.values())
    if isinstance(n, list): return any(has_key(x, name) for x in n)
    return False
if not has_key(d, "k8s_gitops_cluster_labels"):
    role = yaml.safe_load(open(repo + "/hosts/ansible/roles/k8s_gitops/defaults/main.yml"))
    labels = role.get("k8s_gitops_cluster_labels")
    if not isinstance(labels, dict) or labels.get("env") != "prod": die("the k8s_gitops role's default labels do not say env prod")
    v["k8s_gitops_cluster_labels"] = labels
v["ansible_ssh_private_key_file"] = key
v["ansible_ssh_common_args"] = "-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=" + known
v["k8s_gateway_smoke_client"] = "localhost"
v["k8s_certs_smoke_client"] = "localhost"
v["k8s_gitops_source_openbao_in_cluster"] = True
# The notebook CI runner pod is prod's only (docs/runbooks/run-the-notebook-runner-on-c1.md).
v["k8s_gitops_source_notebook_runner"] = True
v["k8s_gitops_source_openbao_seal_node"] = seal
v["k8s_gitops_source_openbao_store_host"] = store
if cidr: v["k8s_gitops_source_openbao_box_cidr"] = cidr
if admin: v["k8s_gitops_source_openbao_admin_address"] = admin
# The rebuild's own: prod's own snapshot back (k8s-restore.yml, k8s-identity-restore.yml), onto stable folder names
# so the new claims find the restored folders, the backup certificates carried over, and no throwaway identity copy.
v["k8s_backup_restore_own_env"] = True
v["k8s_backup_restore_source_host"] = workers[0]
v["k8s_gitops_source_local_path_stable_folders"] = True
v["k8s_backup_azure_seed_dir"] = certs
# With the Proxmox host as the backup target the rebuilt nodes get their old sftp keys back (carried off the nodes in step 1a)
# and name the host by the address read above; the host already lets those keys in, and the box holds no key on the host.
v["k8s_backup_sftp_seed_dir"] = sftp_keys
if pve_addr:
    try: ipaddress.ip_address(pve_addr)
    except ValueError: die("proxmox_host_mgmt_address is not an IP address")
    v["k8s_backup_sftp_seed_address"] = pve_addr
v["k8s_backup_restore_check_identity"] = False
yaml.safe_dump(d, open(dst, "w"), default_flow_style=False)
PY
)" "$pkeys/inventory-hosts.yml" "$inventory/hosts.yml" "$nodekey" "$envdir/known_hosts" "$pkeys" "$keys" "$certs" "$settings" "$repo" "$sftp_keys"; then
  chmod 600 "$inventory/hosts.yml"
  # Every k8s_nodes host as Ansible sees it: plain ssh with the box's key, labelled env prod, at an address, and no
  # value that still names a file on the Mac. The names of the mapped files must exist on the box.
  if ansible-inventory -i "$inventory/" --list | python3 -I -c "$(cat <<'PY'
import json, os, re, sys
nodekey, known, backup_mode = sys.argv[1:4]
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
              "k8s_identity_values_file", "k8s_certs_lab_ca_cert_file", "k8s_certs_lab_ca_key_file", "k8s_identity_theme_dir",
              "k8s_gitops_sso_root_ca_file"):
        p = v.get(k)
        if isinstance(p, str) and p and not os.path.exists(p): bad.append("%s is %s, which is not on the box" % (k, p))
    # The identity role needs <theme>/login/theme.properties (k8s_identity tasks/theme.yml) and would stop on it only after
    # the teardown, in stage identity.
    th = v.get("k8s_identity_theme_dir")
    if isinstance(th, str) and th and os.path.isdir(th) and not os.path.isfile(os.path.join(th, "login", "theme.properties")):
        bad.append("k8s_identity_theme_dir is %s, which has no login/theme.properties" % th)
# The backup target (docs/runbooks/back-up-c1-off-box.md). Azure: each node's certificate is carried to its rebuilt node
# (step 2 of rebuild). The Proxmox host over sftp: each node's own key pair and its pinned host key are carried the same way
# (step 1a), so the host, which already lets those keys in, needs no change and the box needs no key on it; the host's address
# comes from the box's copy of the prod inventory, prod/inventory-hosts.yml (proxmox_host_mgmt_address), read before the proxmox group is dropped.
truthy = lambda x: x is True or str(x).lower() in ("true", "yes", "1")
sftp = sorted(h for h in nodes if truthy(hv.get(h, {}).get("k8s_backup_sftp")))
azure = sorted(h for h in nodes if truthy(hv.get(h, {}).get("k8s_backup_azure_identity")))
if sftp and len(sftp) != len(nodes):
    bad.append("k8s_backup_sftp is true on some prod nodes only: %s" % " ".join(sftp))
elif sftp and azure:
    bad.append("k8s_backup_sftp and k8s_backup_azure_identity are both true on prod nodes; the node env file can name one repository only")
elif sftp:
    for h in sftp:
        if not hv.get(h, {}).get("k8s_backup_sftp_seed_address"):
            bad.append("k8s_backup_sftp is true but the box's copy has no host address for node %s: the box's copy of the prod inventory (prod/inventory-hosts.yml) needs proxmox_host_mgmt_address on its proxmox group, which the controller's prod-files run copies" % h)
elif azure and len(azure) != len(nodes):
    bad.append("k8s_backup_azure_identity is true on some prod nodes only: %s" % " ".join(azure))
for b in sorted(set(bad)): print("FAIL: rebuild-prod: inventory: " + b)
if bad: sys.exit(1)
open(backup_mode, "w").write("sftp\n" if sftp else ("azure\n" if azure else "none\n"))
print("PASS: rebuild-prod: %d prod nodes, plain ssh with the box's key, every private file at the box's copy" % len(nodes))
PY
)" "$nodekey" "$envdir/known_hosts" "$envdir/backup-mode"; then inv_ok=true; else fails=$((fails + 1)); fi
else
  fails=$((fails + 1))
fi

# --- 3. OpenTofu: the box's state is the live prod, and the teardown would destroy only prod's node VMs.
tf=$repo/hosts/terraform/home/k8s
# A prod teardown destroys the node VMs only: prod's state also owns the AlmaLinux image and the template (VM 9000) the nodes clone
# from, and a full destroy would delete both and download the image again. The address names the resource, not an instance
# (an instance's key is a node's hostname), so it destroys every node VM and nothing else.
teardown_target=proxmox_virtual_environment_vm.node
# tf_note <output file>: what to print for a failed OpenTofu step. Fixed facts only, never the step's own text: the output's line
# count and which phrases from a closed list it holds. Its text can carry a private value (a broken env-file line prints the token it
# could not run, and masking cannot catch every address or hostname shape), so no line of it is ever printed.
tf_note() {
  local f=$1 n=0 hit=() p
  [[ -r $f ]] || { printf 'output not readable'; return 0; }
  n=$(grep -c '' "$f" 2>/dev/null || true)
  for p in 'Permission denied' 'No such file' 'command not found' 'Failed to query' 'registry' 'Error'; do
    if grep -q -F -- "$p" "$f" 2>/dev/null; then hit+=("$p"); fi
  done
  printf '%s output line(s); phrases found: %s' "${n:-0}" "$( (IFS=,; printf '%s' "${hit[*]:-none}") )"
}
# shellcheck source=/dev/null
tofu_k8s() { (set -a; . "$tofu_env"; set +a; tofu -chdir="$tf" "$@"); }
if [[ -s $tofu_env && -s $tfstate && -s $tfvars_src ]] && command -v tofu >/dev/null; then
  if tofu_k8s init -input=false -reconfigure -backend-config="path=$tfstate" > "$envdir/tofu-init.out" 2>&1; then
    # The box's copy first: it is the file the rebuild applies (the Mac's tfvars with the box's node key, TFVARS below), so the VMs a
    # box run built hold the box's key in initialization.user_account.keys, and planning them with the Mac's key shows a change there
    # for ever (prod run 4, 2026-11-21: "differs in: initialization" on VMs 200 and 201). VMs built from the Mac hold the Mac's key:
    # the Mac's file is the second try. Either clean says the box's state is the live prod; both changed is the failure.
    planvars=$tfvars
    rc=0; tofu_k8s plan -input=false -lock=false -detailed-exitcode -var-file="$tfvars" -out="$envdir/tofu-plan.bin" > "$envdir/tofu-plan.out" 2>&1 || rc=$?
    if [[ $rc -eq 2 ]]; then
      rc_mac=0; tofu_k8s plan -input=false -lock=false -detailed-exitcode -var-file="$tfvars_src" -out="$envdir/tofu-plan-mac.bin" > "$envdir/tofu-plan-mac.out" 2>&1 || rc_mac=$?
      if [[ $rc_mac -eq 0 ]]; then rc=0 planvars=$tfvars_src; fi
    fi
    case $rc in
      0) if [[ $planvars == "$tfvars" ]]; then pass "OpenTofu: no changes with the box's tfvars copy (the Mac's with the box's node key, as the rebuild applies it), so the box's state is the live prod"
         else pass "OpenTofu: no changes with the Mac's tfvars (the VMs hold the Mac's node key), so the box's state is the live prod"; fi ;;
      2) # What it would change, read from the plan file (which only this user can read): each resource's type and name (with a VM's
         # ID) and its actions, then the names of the attributes that differ. Never an address (its index is a node's hostname) and
         # never a value, and no more than 30 lines. A plan whose only changes are moves of a resource's address in the state (a
         # moved block: nothing changes on the host) is the box's state being older than the code, which the first apply fixes.
         plan_view=$(tofu_k8s show -json "$envdir/tofu-plan.bin" 2>/dev/null | python3 -I -c '
import json, sys
try: plan = json.load(sys.stdin)
except ValueError: print("SUMMARY unreadable"); sys.exit(0)
n = real = moves = 0
for rc in plan.get("resource_changes", []):
    ch = rc.get("change", {}); acts = ch.get("actions", [])
    moved = rc.get("previous_address") and rc.get("previous_address") != rc.get("address")
    if acts == ["no-op"] and moved:
        moves += 1
        if n < 30: print("  plan: %s.%s moved in the state (its address changes; nothing changes on the host)" % (rc.get("type"), rc.get("name")))
        n += 1
        continue
    if acts in (["no-op"], ["read"]): continue
    real += 1
    b, a = ch.get("before") or {}, ch.get("after") or {}
    # Attribute names only, down into a block (initialization.user_account.keys), never a value.
    def paths(x, y, pre=""):
        out = []
        if isinstance(x, list) and len(x) == 1 and isinstance(y, list) and len(y) == 1: x, y = x[0], y[0]
        if isinstance(x, dict) and isinstance(y, dict):
            for k in sorted(set(x) | set(y)):
                out += paths(x.get(k), y.get(k), pre + k + ".")
        elif x != y:
            out.append(pre[:-1])
        return out
    diff = sorted(set(paths(b, a))) if isinstance(b, dict) and isinstance(a, dict) else sorted(k for k in set(b) | set(a) if b.get(k) != a.get(k))
    # type.name and, for a VM, its ID: never rc[address], whose index is a private node hostname.
    vm = b.get("vm_id", a.get("vm_id"))
    what = "%s.%s%s" % (rc.get("type"), rc.get("name"), " vm_id %d" % vm if isinstance(vm, int) else "")
    if n < 30: print("  plan: %s %s; differs in: %s" % (what, "+".join(acts), ", ".join(diff[:12]) or "(unknown until apply)"))
    n += 1
print("SUMMARY real=%d moves=%d" % (real, moves))
' || true)
         if [[ $plan_view == *"SUMMARY real=0 moves="[1-9]* ]]; then
           pass "OpenTofu: the only plan changes are state moves (nothing changes on the host): $(grep -c 'moved in the state' <<< "$plan_view") resource(s)"
         else
           fail "OpenTofu plans changes with the box's tfvars copy and with the Mac's tfvars: the box's state or tfvars differ from the live prod; copy the controller's files again"
           grep -v '^SUMMARY' <<< "$plan_view" || true
         fi ;;
      *) fail "OpenTofu plan failed (rc $rc): $(tf_note "$envdir/tofu-plan.out")" ;;
    esac
    # A targeted destroy refuses a state that still holds resources the code has moved ("Moved resource instances excluded by
    # targeting"), so the plan is made on a COPY of the state that has had the moves written by a refresh-only apply (state
    # only; nothing changes on the host, and the live state is not written). The real teardown does the same first.
    settled=$envdir/state-moves-settled.tfstate
    rc=0
    { cp -- "$tfstate" "$settled" &&
      tofu_k8s init -input=false -reconfigure -backend-config="path=$settled" &&
      tofu_k8s apply -refresh-only -auto-approve -input=false -lock=false -var-file="$planvars" &&
      tofu_k8s plan -input=false -lock=false -destroy -target="$teardown_target" -var-file="$planvars" -out="$envdir/destroy.plan"; } > "$envdir/tofu-destroy.out" 2>&1 || rc=$?
    rm -f -- "$settled" "$settled.backup"
    tofu_k8s init -input=false -reconfigure -backend-config="path=$tfstate" > "$envdir/tofu-init.out" 2>&1 || true
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
      fail "OpenTofu could not plan the teardown (rc $rc): $(tf_note "$envdir/tofu-destroy.out")"
    fi
    rm -f -- "$envdir/destroy.plan" "$envdir/destroy.json" "$envdir/tofu-plan.bin"
  else
    fail "OpenTofu init failed: $(tf_note "$envdir/tofu-init.out")"
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
# The newest run that did more than a teardown, the way `rebuild log` reads it (rebuild.sh): a teardown run after a
# good full run must not hide that run. Dev is torn down after a run: hosts/rebuild-k8s.sh runner_run_teardown tears it
# down at the end of every full run under ephemeral-dev, pass or fail, and the runbook's hand `rebuild teardown` does the same.
# A teardown-only log alone, or newest with no full run behind it, still fails below.
dev_short=""
while read -r f; do
  if grep -Eq '^[0-9TZ:-]+ [a-z0-9-]+ start$' "$f" && ! grep -E '^[0-9TZ:-]+ [a-z0-9-]+ start$' "$f" | grep -vq ' teardown start$'; then
    continue
  fi
  dev_short=$f; break
done < <(ls -1 "$dev_logs"/rebuild-*.log 2>/dev/null | sort -r)
if [[ -z $dev_short ]]; then fail "no dev run other than a teardown is logged on the box; run dev in full first"
elif ! grep -qx 'rebuild: all stages passed' "$dev_short"; then fail "the newest dev run (${dev_short##*/}) did not pass every stage"
elif ! grep -qx "rebuild: central-hub $commit" "$dev_short"; then fail "the newest dev run (${dev_short##*/}) ran another commit than ${commit:0:12}; run dev again first"
else
  # A teardown-only run (rebuild.sh teardown) also ends "all stages passed", so that line alone is no pass.
  # The run must hold a good end line for each stage every full dev run has (rebuild.sh's stage lists).
  not_ended=""
  for s in vms cluster storage restore gitops secrets apps gateway checks; do
    grep -Eq "^[0-9TZ:-]+ $s end rc=0( |\$)" "$dev_short" || not_ended+="$s "
  done
  if [[ -n $not_ended ]]; then fail "the newest dev run (${dev_short##*/}) is not a full run: no good end line for stage(s) ${not_ended% }; run dev in full first"
  else pass "dev passed every stage at ${commit:0:12} (run ${dev_short##*/})"; dev_run=${dev_short##*/}; fi
fi

if [[ $fails -gt 0 ]]; then echo "rebuild-prod: $action: $fails checks failed; nothing was changed"; exit 1; fi
if [[ $action == check ]]; then echo "rebuild-prod: check: every check passed; nothing was changed"; exit 0; fi

# ===== rebuild: the checks before a teardown (D-0035 rule 5). Any failure stops the run before anything is destroyed.
echo "rebuild-prod: rebuild of prod at ${commit:0:12}, owner tap $tap, after dev run $dev_run"
ap() { (cd "$repo/hosts/ansible" && ansible-playbook -i "$inventory/" "$@"); }
old_args="ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$old_known'"

# 1a. Each node's sftp key pair and the host key it pinned, kept in the keys folder; never printed. Only with the Proxmox host as
# the backup target (k8s_backup_sftp): the rebuilt node gets the same key back, which the host already lets in (the box holds no
# key on the host to let a new one in), and the playbooks read the host's key from the carried known_hosts. Before the drill,
# which runs the backup play on the live nodes with this same inventory.
if [[ $(cat -- "$envdir/backup-mode" 2>/dev/null) == sftp ]]; then
install -d -m 700 "$sftp_keys"
while read -r name host user; do
  sudo_=""; [[ $user == root ]] || sudo_="sudo -n "
  # After a run that stopped past its teardown the nodes are rebuilt and empty: their keys are the ones that run kept here before it
  # destroyed them (the dev run of 2026-11-21 showed the read failing on the empty nodes; prod run 5 stopped there). Kept and whole, they stand.
  if [[ -n $torn ]] && grep -q -- 'PRIVATE KEY-----' "$sftp_keys/$name.key" 2>/dev/null && grep -q -- '^ssh-ed25519 ' "$sftp_keys/$name.pub" 2>/dev/null &&
     grep -q -- ' ssh-ed25519 ' "$sftp_keys/$name.known_hosts" 2>/dev/null; then
    echo "rebuild-prod: node $name: the stopped run ($torn) kept its sftp backup key, public key and pinned host key before its teardown; they stand"
    continue
  fi
  for f in id_ed25519:key id_ed25519.pub:pub known_hosts:known_hosts; do
    ssh_node "$host" "$user" "${sudo_}cat /etc/central-hub/backup-ssh/${f%%:*}" > "$sftp_keys/$name.${f##*:}.part" </dev/null ||
      { rm -f -- "$sftp_keys/$name".*.part; echo "FAIL: rebuild-prod: could not read node $name's backup ssh file ${f%%:*}; nothing was destroyed"; exit 1; }
  done
  grep -q -- 'PRIVATE KEY-----' "$sftp_keys/$name.key.part" && grep -q -- '^ssh-ed25519 ' "$sftp_keys/$name.pub.part" &&
    grep -q -- ' ssh-ed25519 ' "$sftp_keys/$name.known_hosts.part" ||
    { rm -f -- "$sftp_keys/$name".*.part; echo "FAIL: rebuild-prod: node $name's backup ssh key, public key or pinned host key is not whole; nothing was destroyed"; exit 1; }
  for e in key pub known_hosts; do mv -- "$sftp_keys/$name.$e.part" "$sftp_keys/$name.$e"; chmod 600 "$sftp_keys/$name.$e"; done
done < "$node_list"
echo "PASS: rebuild-prod: each node's sftp backup key and pinned host key kept for its rebuilt node"
fi

# 1. A backup of every node now, then the restore tests on it.
# The restore tests restore into a temporary folder on each node, never over its data. The first worker's
# volume test and the control plane's etcd test must each name the snapshot they restored: a node with no
# volume record passes with nothing to test, and that is not a backup of prod's data.
if [[ -n $pin ]]; then
  pass "restore snapshot ${pin:0:12} is pinned${torn:+ (the last run, $torn, stopped after its teardown)}${given_pin:+, named by the go}: no backup is taken of the nodes, so a snapshot of rebuilt, empty nodes can never be the one that comes back or make the repository forget it"
else
drill_out=$envdir/drill-$stamp.log
ap playbooks/k8s-backup.yml --tags drill -e k8s_backup_drill=true -e "$old_args" | tee "$drill_out" ||
  { echo "FAIL: rebuild-prod: the backup and restore test before the teardown failed; nothing was destroyed"; exit 1; }
vol_pass=$(grep -oE 'PASS: volume restore test, [1-9][0-9]* folders, [0-9]+ database dumps, snapshot [0-9a-f]{8} of [0-9T:-]+' "$drill_out" | head -n 1 || true)
etcd_pass=$(grep -oE 'PASS: etcd restore test, revision [0-9]+, [0-9]+ keys under /, key [^,]+ present, snapshot [0-9a-f]{8} of [0-9T:-]+' "$drill_out" | head -n 1 || true)
if [[ -z $vol_pass || -z $etcd_pass ]]; then
  echo "FAIL: rebuild-prod: the drill named no tested volume snapshot or no tested etcd snapshot; nothing was destroyed"; exit 1
fi
echo "PASS: rebuild-prod: every prod node backed up now, and its restore test passed: ${vol_pass#PASS: }; ${etcd_pass#PASS: }"
  pin=$(sed -E 's/.*snapshot ([0-9a-f]{8}) of .*/\1/' <<< "$vol_pass")
  # The restore's own folder mapping, run strictly on that snapshot by the drill (k8s_backup drill.yml, c1-restore-volumes.sh plan):
  # one folder for each claim, or nothing is destroyed. The full ID it names must be the snapshot the restore test passed on.
  plan_pass=$(grep -oE 'PASS: plan: snapshot [0-9a-f]{64}: [0-9]+ folders map to [0-9]+ claims, no claim has more than one folder' "$drill_out" | head -n 1 || true)
  if [[ -z $plan_pass ]]; then
    echo "FAIL: rebuild-prod: the drill's mapping of the volume snapshot (c1-restore-volumes.sh plan) did not pass: see the plan's lines above; nothing was destroyed"; exit 1
  fi
  plan_id=$(grep -oE '[0-9a-f]{64}' <<< "$plan_pass")
  if [[ $plan_id != "$pin"* ]]; then
    echo "FAIL: rebuild-prod: the drill mapped snapshot ${plan_id:0:8} but its restore test passed on ${pin}; nothing was destroyed"; exit 1
  fi
  pin=$plan_id
  echo "PASS: rebuild-prod: the restore's folder mapping on snapshot ${plan_id:0:12} gives each claim exactly one folder (${plan_pass#PASS: plan: })"
fi

# 2. Each node's backup certificate and key ID, kept in the keys folder; never printed. Only with the Azure sign-in
# (k8s_backup_azure_identity): with none, the nodes hold no certificate and there is nothing to carry.
if [[ $(cat -- "$envdir/backup-mode" 2>/dev/null) == azure ]]; then
install -d -m 700 "$certs"
while read -r name host user; do
  sudo_=""; [[ $user == root ]] || sudo_="sudo -n "
  # A stopped-past-teardown run left the nodes rebuilt and empty: the certificate it kept before its teardown stands when whole.
  if [[ -n $torn && -s $certs/$name.pem.keyid ]] && grep -q -- '-----BEGIN CERTIFICATE-----' "$certs/$name.pem" 2>/dev/null &&
     grep -q -- 'PRIVATE KEY-----' "$certs/$name.pem" 2>/dev/null; then
    echo "rebuild-prod: node $name: the stopped run ($torn) kept its backup certificate before its teardown; it stands"
    continue
  fi
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
else
  echo "PASS: rebuild-prod: no Azure sign-in on the prod nodes (k8s_backup_azure_identity off), so no backup certificate to carry"
fi

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
if ssh_node "$seal_host" "$seal_user" "${sudo_}cat /var/lib/central-hub/openbao-seal/seal-1.key" > "$seal_tmp/node.key" </dev/null; then
  cmp -s "$seal_tmp/node.key" "$seal_tmp/openbao-seal.key" ||
    { echo "FAIL: rebuild-prod: the seal key's SOPS copy differs from the seal node's key (run openbao-prod seal-copy); nothing was destroyed"; exit 1; }
  rm -f -- "$seal_tmp/node.key"
  echo "PASS: rebuild-prod: the seal key's SOPS copy equals the seal node's key"
elif [[ -n $torn ]]; then
  # The rebuilt seal node may hold no seal key yet. That stands only when all three hold: the stopped run's own log says it compared the
  # SOPS copy with the live key before its teardown, the SOPS file is older than that log (not replaced since), and the node says
  # cleanly that the file is not there (test ! -e); any other failure (a sudo or ssh error, an unreadable file) refuses.
  rm -f -- "$seal_tmp/node.key"
  seal_file=/var/lib/central-hub/openbao-seal/seal-1.key
  if ! grep -qxF "PASS: rebuild-prod: the seal key's SOPS copy equals the seal node's key" -- "$logs/$torn"; then
    echo "FAIL: rebuild-prod: the seal node's key could not be read, and the log of the stopped run ($torn) does not show it compared the SOPS copy with the live key; nothing was destroyed"; exit 1
  elif [[ ! $seal_sops -ot $logs/$torn ]]; then
    echo "FAIL: rebuild-prod: the seal node's key could not be read, and the SOPS copy ($seal_sops) is not older than the stopped run's log ($torn), so it may have changed since that run compared it; nothing was destroyed"; exit 1
  elif ! ssh_node "$seal_host" "$seal_user" "${sudo_}test ! -e $seal_file" </dev/null >/dev/null 2>&1; then
    echo "FAIL: rebuild-prod: the seal node's key could not be read and the node does not say the file is absent (an ssh or sudo error, or a file that exists but cannot be read); nothing was destroyed"; exit 1
  fi
  echo "rebuild-prod: the seal node is rebuilt and the node says the seal key file is absent; the SOPS copy (32 bytes, decrypts with the box's identity, older than the stopped run's log) is the key that run ($torn) compared with the live one before its teardown"
else
  echo "FAIL: rebuild-prod: could not read the seal key on the seal node; nothing was destroyed"; exit 1
fi

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

# The restore snapshot is pinned from here until a run ends well: a later run takes it from this file, and never takes a backup.
printf '%s\n%s %s\n' "$pin" "$(date -u +%FT%TZ)" "${log##*/}" > "$pin_file"
echo "rebuild-prod: the restore snapshot is pinned: ${pin:0:12}${given_pin:+ (full ID given)}; kept in the box's state until a run ends well"

# From here prod's cluster is built with stable folder names, which the box's other prod copies follow (openbao-prod).
date -u +%FT%TZ > "$work/state/prod-stable-folders"
# The rebuilt nodes have new host keys: the build starts with no known hosts.
rm -f -- "$envdir/known_hosts" "$envdir/known_hosts.old" "$work/c1-ansible/known_hosts"

# certs runs before gateway: the Gateway's HTTPS listener waits on the certificate's Secret, and `apps` leaves out the two apps that
# need what certs makes (APPS_DEFER); `checks` waits for every app (prod run 6, 2026-11-21, stopped at apps on gateway and jellyfin).
stages="vms cluster storage openbao-seal restore gitops secrets apps certs gateway identity identity-db ui backup checks"
cat > "$envdir/rebuild.env" <<ENV
ENV_NAME=prod
VM_ID_MIN=$vm_min
VM_ID_MAX=$vm_max
TFVARS=$tfvars
TFSTATE=$tfstate
TOFU_ENV=$tofu_env
INVENTORY=$inventory/
STAGES="$stages"
APPS_DEFER="gateway jellyfin"
TEARDOWN_TARGET=$teardown_target
SECRET_SOURCE_FILE=$pkeys/secret-source.env
OPENBAO_SEAL_KEY_FILE=$seal_tmp/openbao-seal.key
RESTORE_HOOK='cd "\$REPO/hosts/ansible" && ansible-playbook -i "\$INVENTORY" playbooks/k8s-restore.yml -e k8s_backup_enabled=false -e k8s_backup_restore_snapshot=$pin'
RESTORE_CHECK_HOOK='cd "\$REPO/hosts/ansible" && ansible-playbook -i "\$INVENTORY" playbooks/k8s-restore.yml --tags restore_check -e k8s_backup_enabled=false'
ENV
chmod 600 "$envdir/rebuild.env"
echo "rebuild-prod: teardown and build start: $stages"
rc=0
bash "$repo/hosts/rebuild-k8s.sh" "$envdir" --teardown || rc=$?
if [[ $rc -eq 0 ]]; then
  # The carried sftp private keys have done their job once the rebuilt nodes hold them and the backup stage and checks passed;
  # the host accepts those keys as the writer, so the box must not keep a key on the host (D-0042 rule 6, an access right
  # under the standing go of D-0061, named in the PR). On a failed run they stay: a stopped run is resumed from them.
  if [[ -d $sftp_keys ]]; then rm -rf -- "$sftp_keys"; echo "rebuild-prod: the carried sftp keys were deleted from the box"; fi
  rm -f -- "$pin_file"; echo "rebuild-prod: the restore pin was cleared: the run ended well"
  echo "PASS: rebuild-prod: prod torn down and built again at ${commit:0:12}, data back, backups on"
else echo "FAIL: rebuild-prod: the one command stopped (rc $rc); rebuild-prod log names the stage"; fi
exit "$rc"
