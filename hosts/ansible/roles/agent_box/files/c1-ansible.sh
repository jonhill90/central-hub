#!/bin/bash
# /usr/local/libexec/agent-box/c1-ansible.sh: run one named Ansible playbook against prod's c1 from the agent box, so the
# change to c1 leaves the Mac. It runs as user `keys` through sudo, with the box's own prod node key (the key openbao-prod
# makes), so the session never sees a key, a values file or the inventory. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/c1-ansible.sh list|check <name>|apply <name> <clearance id>|log
# list    the names this wrapper runs.
# check   read-only: the playbook with --check --diff. It changes nothing on c1.
# apply   the playbook for real. <clearance id> is the cmsg_ id of the reviewer's clearance of the head that is on main
#         (D-0042 rule 1); it goes into the log, and the wrapper cannot read the chat to check it.
# log     the newest run's lines: the action, the commit, the clearance id, and the PASS, FAIL, task and recap lines, and the
#         "delete would remove:" lines of the observability role (what each of its deletes would remove).
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
# gateway: the shared Gateway and its node firewall ports (tag gateway only: not the smoke test, which applies and removes an app).
# gitops: the GitOps engine's source, web UI route and sign-in settings (tags source, ui, sso only: never install, the pinned
# upstream install of Argo CD). It passes k8s_gitops_source_jellyfin_setup=false, because prod is rebuilt from a restore of its own Jellyfin config
# (with the admin password the config holds), which a fresh admin Secret cannot match, and it maps the sign-in's CA file to <keys>/prod/lab-ca/root.crt. It also sets the root Application's own variables (the store's address and seal node, the notebook runner, the stable local-path folders) from the box's store settings, through the file prod's rebuild uses too (prod-root-vars.py), so `check gitops` plans no change to them; it stops when the settings are missing. observability: metrics-server, kube-prometheus-stack, Loki, Alloy and Grafana's route, with every tag the
# role has named, so a tag added later is not run until this line names it. None of them needs a private file on the box: the inventory carries their values.
# certs: re-runs only the certificate work on prod (playbooks/k8s-certs.yml, tag issue: the lab CA's intermediate Secret, the ClusterIssuers
# and the Gateway's wildcard Certificate), in place, with no teardown. It reads three files the controller's prod-files run and prod's rebuild
# already put on the box (<keys>/prod/cloudflare-dns01-token.txt, <keys>/prod/lab-ca/c1-intermediate-chain.crt and c1-intermediate.key; the
# inventory's own paths for them are the Mac's and are mapped here, as rebuild-prod.sh maps them), so it uses the same CA and the same
# names; a changed Certificate makes cert-manager issue again with a new key (rotationPolicy Always). It never installs cert-manager (tag certmanager),
# never touches the nodes' trust (tag nodetrust) and never deletes: a run with issuing off in the inventory would remove the issuers, so
# `apply certs` stops before that. `check certs` prints the diff of what would change.
# clients: makes sure clients `proxmox`, `openbao`, `opnsense` and `central-hub-app` are in the live realm (tags secrets and clients, the role's add-in-place path: files/ensure-client.sh
# creates a client that is missing and updates one that is there; users, groups and the other clients are not touched, and the realm is
# never replaced). Unlike `identity` it does not run the operator, database or keycloak tags, so a pending Keycloak or operator version
# change on prod is not rolled out by it.
# users: adds the sign-in test user, `signin-test`, to the live realm (tags secrets and users, which never replace the realm: the
# role's keycloak tag does that and this name does not run it). The user must be in the private inventory's k8s_identity_extra_users,
# or the run stops at user-json.py; a user already there is left as it is. The secrets tag also adds a random password and seed to the
# box's own identity.env for a key it lacks, and writes the realm's Secret in c1.
# identity-values: adds a random value for each key the realm needs that the box's own identity.env lacks (the role's first task,
# tags always: secrets.yml, `openssl rand -hex 32` for a client secret, only the key's name printed), and nothing else: no cluster
# call, no realm, no secret object. It exists so a new client's secret (OPNSENSE_CLIENT_SECRET) is made on the box, then written to the
# store by `secrets-store-prod put-apps`, before the `clients` run makes the ExternalSecret that reads it. It changes a file, so there is no
# check: apply only, with a clearance id.
# backup-status: reads the c1 nodes' backup timers, last results, journal PASS/FAIL lines and restic snapshots (playbooks/k8s-backup-status.yml:
# every task only reads; restic runs with --no-lock). It changes nothing, so check and apply both read; it runs no backup and no restore.
# backup-restore-test: starts each node's c1-restore-test.service now (the Sunday timer's own unit: restic check, then the newest snapshots restored
# into temporary folders and compared, never over a volume) and stops unless each node names the snapshot it restored and leaves no folder behind.
# check starts nothing; apply starts it. It takes no backup.
# restore-inspect: reads what a restore would do with prod's newest volume snapshot (the one in the box's restore pin, when a rebuild
# stopped after its teardown): on each worker, c1-restore-volumes.sh inspect, which lists every folder in the snapshot with its
# files, bytes and newest file time, which folder each claim would take (the volume the etcd backup binds it to) and why one is not
# settled. It writes nothing: restic runs with --no-lock, and no file is written but a temporary one it removes. check and apply both read.
# Like backup-status it starts from no known hosts, so nodes rebuilt since the last run (new host keys) are reachable.
# backup-check: plays playbooks/k8s-backup.yml in check mode only, to prove the sftp alias tasks (the carried key seeds, the host address
# from the box's copy of the prod inventory) before a prod rebuild; apply is refused, because the wrapper never takes a backup. The seed folder is the one
# rebuild-prod.sh fills (<keys>/prod/backup-sftp); the env file is the box's own <keys>/c1-backup.env, as in rebuild-prod.sh (the first run's play 3 stopped on the default path under the keys user's home); the host address is read before the proxmox group is dropped, as rebuild-prod.sh does.
declare -A playbook=([identity]=playbooks/k8s-identity.yml [gateway]=playbooks/k8s-gateway.yml [gitops]=playbooks/k8s-gitops.yml [observability]=playbooks/k8s-observability.yml [users]=playbooks/k8s-identity.yml [clients]=playbooks/k8s-identity.yml [identity-values]=playbooks/k8s-identity.yml [backup-status]=playbooks/k8s-backup-status.yml [backup-restore-test]=playbooks/k8s-backup-restore-test.yml [backup-check]=playbooks/k8s-backup.yml [restore-inspect]=playbooks/k8s-restore-inspect.yml [certs]=playbooks/k8s-certs.yml)
declare -A needs_file=([identity]="$keys/prod/identity.env" [users]="$keys/prod/identity.env" [clients]="$keys/prod/identity.env" [identity-values]="$keys/prod/identity.env")
declare -A needs_var=([identity]=k8s_identity_values_file [users]=k8s_identity_values_file [clients]=k8s_identity_values_file [identity-values]=k8s_identity_values_file)
# Fixed extra variables per name. identity, users and clients also set k8s_identity_secrets_store=openbao, so the realm's Secrets
# are made as ExternalSecrets on store `openbao` (plan step 8a; put-apps must have written the values first). identity never replaces realm lab on prod: the role's default deletes the realm and
# imports it again when its code changes, which on prod ends every sign-in and drops enrolled one-time codes. With false
# the realm is only made when missing; a client is added in place by the role's clients tag.
declare -A fixed_vars=([identity]="k8s_identity_realm_replace=false k8s_identity_secrets_store=openbao" [users]="k8s_identity_realm_replace=false k8s_identity_secrets_store=openbao" [clients]="k8s_identity_realm_replace=false k8s_identity_secrets_store=openbao" [backup-check]="k8s_backup_env_file=$keys/c1-backup.env" [gitops]="k8s_gitops_source_jellyfin_setup=false")
# Tags per name. identity runs every task plus the clients tag, which is off by default. The tag acts only on the clients in
# k8s_identity_ensure_clients (empty by default), so the wrapper names them: proxmox, the client the realm gained after prod's
# realm was made. It is added in place, with no realm replace. Name another client here, in its own pull request, to add it.
declare -A fixed_tags=([identity]="all,clients" [gateway]="gateway" [gitops]="source,ui,sso" [observability]="metrics_server,metrics,logs,route,proof" [users]="secrets,users" [clients]="secrets,clients" [identity-values]="always" [certs]="issue")
declare -A fixed_json=([identity]='{"k8s_identity_ensure_clients":["proxmox"]}' [users]='{"k8s_identity_ensure_users":["signin-test"]}' [clients]='{"k8s_identity_ensure_clients":["proxmox","openbao","opnsense","central-hub-app"]}')

usage() { echo "usage: c1-ansible list|check <name>|apply <name> <clearance id>|log" >&2; exit 2; }
action=${1:-} name='' clearance=''
case $action in
  list | log) [[ $# -eq 1 ]] || usage ;;
  check) [[ $# -eq 2 ]] || usage; name=$2
    [[ $name != identity-values ]] || { echo "c1-ansible: identity-values has no check: it only adds missing keys to the box's identity.env; use apply" >&2; exit 2; } ;;
  apply)
    [[ $# -eq 3 ]] || usage
    name=$2 clearance=$3
    [[ $name != backup-check ]] || { echo "c1-ansible: backup-check is check only; it never takes a backup" >&2; exit 2; }
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
  sed -E 's/\x1b\[[0-9;]*m//g' -- "$newest" | grep -E '^(c1-ansible:|PLAY RECAP|TASK \[|.*(PASS|FAIL|SKIP):|.*delete would remove:|fatal:|[^ ]+ +: ok=)' | cut -c1-200 | tail -n 60 || true
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
if [[ $name == certs ]]; then
  for f in cloudflare-dns01-token.txt lab-ca/c1-intermediate-chain.crt lab-ca/c1-intermediate.key; do
    [[ -s $keys/prod/$f ]] || { echo "c1-ansible: $keys/prod/$f is missing; the controller's prod-files run puts it there" >&2; exit 1; }
  done
fi
[[ -n ${fixed_vars[$name]:-} ]] && extra+=(-e "${fixed_vars[$name]}")
[[ -n ${fixed_tags[$name]:-} ]] && extra+=(--tags "${fixed_tags[$name]}")
[[ -n ${fixed_json[$name]:-} ]] && extra+=(-e "${fixed_json[$name]}")
if [[ $name == restore-inspect && -s $work/state/prod-restore-pin ]]; then
  pin=$(head -n 1 -- "$work/state/prod-restore-pin")
  [[ $pin =~ ^[0-9a-f]{8,64}$ ]] && extra+=(-e "restore_inspect_snapshot=$pin")
fi

mkdir -p "$envdir" "$logs" "$work/state"
chmod 700 "$envdir"
# A read-only name starts from no known hosts: a rebuilt node has a new host key, and the old one would stop the run.
case $name in backup-status | restore-inspect) rm -f -- "$envdir/known_hosts" ;; esac
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
# The folder of carried sftp files the plays read. A prod rebuild fills <keys>/prod/backup-sftp; backup-check has no rebuild, so it
# reads only each live node's pinned host key (public) into its own folder, below, and no private key is ever copied for it.
seed_dir=$keys/prod/backup-sftp
[[ $name != backup-check ]] || seed_dir=$work/state/backup-check-seed
python3 -I -c "$(cat <<'PY'
import ipaddress, json, os, sys, yaml
src, dst, key, known, themes, sftp_keys, which, settings, rootvars = sys.argv[1:10]
def die(m):
    print("c1-ansible: " + m, file=sys.stderr); sys.exit(1)
d = yaml.safe_load(open(src))
# The Proxmox web UI's DNS names (proxmox_cert_names, on the proxmox group or its hosts) are read before the group is dropped: the
# Keycloak client `proxmox` is rendered only when k8s_identity_proxmox_hosts holds them, and the group's logins and keys must not
# reach the box. Only the names pass, as a literal on k8s_nodes; the box's copy is private (0600), nothing is printed but a count.
def pve_names(n):
    if isinstance(n, dict):
        p = n.get("proxmox")
        if isinstance(p, dict) and ("hosts" in p or "children" in p or "vars" in p):
            found = []
            for part in [p.get("vars")] + list((p.get("hosts") or {}).values()):
                v = (part or {}).get("proxmox_cert_names") if isinstance(part, dict) else None
                if isinstance(v, list): found += [x for x in v if isinstance(x, str) and x]
            return found
        for v in n.values():
            r = pve_names(v)
            if r: return r
    elif isinstance(n, list):
        for i in n:
            r = pve_names(i)
            if r: return r
    return []
names = pve_names(d)
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
        "ansible_private_key_file", "ansible_host_key_checking"}
exec(open(rootvars).read())   # prod-root-vars.py: the root Application's variables, shared with rebuild-prod.sh
DROP |= ROOT_VARS_DROP
def walk(n):
    if isinstance(n, dict):
        for k in list(n):
            if k in DROP: del n[k]
            elif k == "proxmox" and isinstance(n[k], dict) and ("hosts" in n[k] or "children" in n[k] or "vars" in n[k]): del n[k]
            else: walk(n[k])
    elif isinstance(n, list):
        for i in n: walk(i)
walk(d)
# The theme folder the inventory names is a path on the controller. On the box it is the copy the controller's prod-files run
# puts under <keys>/prod/identity-theme/<the folder's own name>: the name stays, because it is the theme's name in Keycloak.
def theme(n):
    if isinstance(n, dict):
        for k in list(n):
            if k == "k8s_identity_theme_dir" and isinstance(n[k], str) and n[k].strip("/"): n[k] = themes + "/" + n[k].rstrip("/").rsplit("/", 1)[-1]
            else: theme(n[k])
    elif isinstance(n, list):
        for i in n: theme(i)
theme(d)
# Argo CD's sign-in trusts the lab root: k8s_gitops_sso_root_ca_file names a path on the controller, and on the box it is the copy
# the controller's prod-files run puts at <keys>/prod/lab-ca/root.crt, the same file rebuild-prod.sh maps it to. Without the
# map, `gitops` (tag sso) stops at "The CA file is a certificate" on a path the box does not have.
def sso_ca(n):
    if isinstance(n, dict):
        for k in list(n):
            if k == "k8s_gitops_sso_root_ca_file" and isinstance(n[k], str) and n[k]: n[k] = os.path.dirname(themes.rstrip("/")) + "/lab-ca/root.crt"
            else: sso_ca(n[k])
    elif isinstance(n, list):
        for i in n: sso_ca(i)
sso_ca(d)
# `certs` reads the Cloudflare token and the lab CA's intermediate (chain and key); the inventory names them on the controller,
# and on the box they are the copies in <keys>/prod, the same three paths rebuild-prod.sh maps them to.
CERT_FILES = {"k8s_certs_cloudflare_token_file": "cloudflare-dns01-token.txt",
              "k8s_certs_lab_ca_cert_file": "lab-ca/c1-intermediate-chain.crt",
              "k8s_certs_lab_ca_key_file": "lab-ca/c1-intermediate.key"}
def cert_files(n):
    if isinstance(n, dict):
        for k in list(n):
            if k in CERT_FILES and isinstance(n[k], str) and n[k]: n[k] = os.path.dirname(themes.rstrip("/")) + "/" + CERT_FILES[k]
            else: cert_files(n[k])
    elif isinstance(n, list):
        for i in n: cert_files(i)
cert_files(d)
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
# The root Application's own variables, the same as prod's rebuild passes (prod-root-vars.py): without them `gitops` plans to drop the
# store's admin address, the notebook runner and the stable local-path folders. `gitops` needs the settings; the other names carry them
# when the box has them, and they change nothing a play outside the root's source reads.
hostnames = set()
def hosts(n):
    if isinstance(n, dict):
        for k, x in n.items():
            if k == "hosts" and isinstance(x, dict): hostnames.update(x)
            else: hosts(x)
hosts(g)
if os.path.isfile(settings):
    rs = read_root_settings(settings, die)
    set_root_vars(v, hostnames, *rs, die)
elif which == "gitops": die("the store's settings %s are missing; gitops builds the root Application from them" % settings)
if names:
    v["k8s_identity_proxmox_hosts"] = sorted(set(names))
    print("c1-ansible: %d Proxmox web names passed to the identity play" % len(set(names)))
import ipaddress
v["k8s_backup_sftp_seed_dir"] = sftp_keys
if pve_addr:
    try: ipaddress.ip_address(pve_addr)
    except ValueError: die("proxmox_host_mgmt_address is not an IP address")
    v["k8s_backup_sftp_seed_address"] = pve_addr
if which == "backup-check":
    print("c1-ansible: backup alias: the host address was %s in the inventory" % ("found" if pve_addr else "NOT found (proxmox_host_mgmt_address on the proxmox group)"))
v["ansible_ssh_private_key_file"] = key
v["ansible_ssh_common_args"] = "-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=" + known
# The k8s_certs role's arg spec renders every default, even under tag issue, and k8s_certs_smoke_client defaults to
# groups['proxmox'] | first, a group this inventory copy drops: `check certs` on the box stopped there (07:02Z 2026-11-22). The
# same two values rebuild-prod.sh sets: the smoke client is the box itself, and its root file is in the run's own folder (keys owns it).
v["k8s_certs_smoke_client"] = "localhost"
v["k8s_certs_smoke_root_file"] = known.rsplit("/", 1)[0] + "/lab-root-ca.crt"
yaml.safe_dump(d, open(dst, "w"), default_flow_style=False)
PY
)" "$inv_src" "$inventory/hosts.yml" "$nodekey" "$envdir/known_hosts" "$keys/prod/identity-theme" "${seed_dir}" "$name" "$work/openbao-prod.json" "$libexec/prod-root-vars.py" || exit 1
chmod 600 "$inventory/hosts.yml"

# Every k8s node: plain ssh to ansible_host with the box's key and nothing else; no host labelled another env than prod.
ansible-inventory -i "$inventory/" --list | python3 -I -c "$(cat <<'PY'
import json, os, sys
nodekey, known, which = sys.argv[1:4]
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
    if which == "certs":
        for need in ("k8s_certs_issue", "k8s_certs_lab_ca"):
            if v.get(need) is not True: die("host %s has %s other than true; `certs` only issues, and with it off the role would remove the issuers and the certificate, which this wrapper never does" % (h, need))
        for need in ("k8s_certs_cloudflare_token_file", "k8s_certs_lab_ca_cert_file", "k8s_certs_lab_ca_key_file"):
            if not v.get(need): die("host %s has no %s; the prod inventory must name it (c1-ansible maps it to the box's copy)" % (h, need))
    env = (v.get("k8s_gitops_cluster_labels") or {}).get("env", "prod")
    if env != "prod": die("inventory host %s is labelled env %s, not prod; refusing" % (h, env))
    t = v.get("k8s_identity_theme_dir")
    if isinstance(t, str) and t and not os.path.isfile(os.path.join(t, "login", "theme.properties")):
        die("k8s_identity_theme_dir is %s, which holds no login/theme.properties on the box; the controller's prod-files run copies the theme folder there (agent_box_prod_theme_src). Nothing was run, so prod's current theme stays" % t)
print("c1-ansible: %d prod nodes, plain ssh with the box's key" % len(nodes))
PY
)" "$nodekey" "$envdir/known_hosts" "$name" || exit 1

if [[ $name == backup-check ]]; then
  rm -rf -- "$seed_dir"; install -d -m 700 "$seed_dir"
  read_n=0
  while read -r n h u; do
    sudo_=""; [[ $u == root ]] || sudo_="sudo -n "
    if ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$envdir/known_hosts" -i "$nodekey" "$u@$h" \
         "${sudo_}cat /etc/central-hub/backup-ssh/known_hosts" > "$seed_dir/$n.known_hosts" 2>/dev/null && grep -q ' ssh-ed25519 ' "$seed_dir/$n.known_hosts"; then
      read_n=$((read_n + 1))
    else rm -f -- "$seed_dir/$n.known_hosts"; fi
  done < <(ansible-inventory -i "$inventory/" --list | python3 -I -c '
import json, sys
inv = json.load(sys.stdin); hv = inv["_meta"]["hostvars"]
def members(g):
    out = set(inv.get(g, {}).get("hosts", []))
    for c in inv.get(g, {}).get("children", []): out |= members(c)
    return out
for h in sorted(members("k8s_nodes")): print(h, hv[h]["ansible_host"], hv[h].get("ansible_user", "root"))')
  echo "c1-ansible: backup-check: the pinned host key was read from $read_n node(s) (public keys only)"
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
log=$logs/run-$stamp.log
exec > >(tee -a "$log") 2>&1
echo "c1-ansible: $action $name at central-hub $commit${clearance:+, clearance $clearance}"
mode=(--check --diff)
[[ $action == apply ]] && mode=()
(cd "$repo/hosts/ansible" && ansible-playbook -i "$inventory/" "${playbook[$name]}" "${extra[@]}" "${mode[@]}")
echo "c1-ansible: $action $name done"
