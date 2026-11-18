#!/bin/bash
# /usr/local/libexec/agent-box/rebuild.sh: run the one-command rebuild of the DEV Kubernetes layer
# (hosts/rebuild-k8s.sh, docs/runbooks/rebuild-k8s-layer-with-one-command.md) from the agent box.
# It runs as user `keys` through sudo, so the session that asks for it never sees the Proxmox
# token, the node SSH key or the dev inventory. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/rebuild.sh up|rebuild|teardown|identity|log|diag
# up: all stages. rebuild: tear the dev VMs down first, then all stages. teardown: only the teardown.
# identity: only the stage identity-keycloak (k8s-identity.yml --tags secrets,keycloak,signin: Keycloak and its
# realm, then the owner's sign-in proof, step names and HTTP codes only) on the existing dev
# cluster. Same dev guard, lock, checkout and log as the other runs; `log` shows it.
# Dev only: the env file below fixes ENV_NAME=dev and the dev VM range 250-257, and rebuild-k8s.sh
# refuses a tfvars whose VM IDs fall outside it or whose node_vnet isn't "dev". Only code on main
# runs with the keys; there is no way to name another branch.
# log: print the newest run's stage lines and its PASS/FAIL lines, nothing else (the raw log can quote the realm
# and the nodes' output). A newer run that only tore dev down is named in one line and skipped, so it can't hide
# a failed run's diag. It takes no argument and reads no other file.
# diag: read-only look at the dev cluster, for a failed apps stage: each dev VM's memory and CPU on Proxmox, the
# node's memory, each dev node's free memory, load and pressure, the Argo CD applications' sync and
# health, the newest events in the alerts and monitoring namespaces, pods that are not running, and
# the monitoring pods and volume claims, and why each application is not Synced and Healthy with the last log lines of
# each pod in Error (scrubbed). With no dev VM running it prints the Proxmox sections and one line "dev nodes: none running",
# and skips the sections that reach a node over ssh. Fixed commands, no argument, no write, no Secret read; it
# uses the inventory the last run made and does not touch the checkout or the run lock.
set -euo pipefail
umask 077

if [[ ${1:-} == log && $# -eq 1 ]]; then
  # The newest run that did more than a teardown: a `rebuild teardown` after a failed run must not hide that run's
  # stage and diag lines (2026-11-18 07:43 UTC). A newer teardown-only run gets one line of its own.
  newest="" td=""
  while read -r f; do
    if grep -Eq '^[0-9TZ:-]+ [a-z0-9-]+ start$' "$f" && ! grep -E '^[0-9TZ:-]+ [a-z0-9-]+ start$' "$f" | grep -vq ' teardown start$'; then
      [[ -n $td ]] || td=$f
      continue
    fi
    newest=$f; break
  done < <(ls -1 /var/lib/agent-box/rebuild-dev/logs/rebuild-*.log 2>/dev/null | sort -r)
  [[ -n $td ]] && echo "newer teardown-only run: ${td##*/}: $(grep -E ' teardown end ' "$td" | tail -n 1)"
  [[ -n $newest ]] || { echo "rebuild: no run other than a teardown has been logged yet" >&2; exit 1; }
  echo "run: ${newest##*/}"
  cat -- "$newest"
  sed -E 's/\x1b\[[0-9;]*m//g' -- "${newest%.log}.raw" 2>/dev/null | grep -E '(^|[^A-Za-z])(PASS|FAIL):' | cut -c1-200 | head -n 60 || true
  exit 0
fi

action=${1:-}
case $action in
  up) extra=() ;;
  rebuild) extra=(--teardown) ;;
  teardown) extra=(--only teardown) ;;
  identity) extra=(--only identity-keycloak) ;;
  diag) extra=() ;;   # handled below, before anything is changed
  *) echo "usage: rebuild up|rebuild|teardown|identity|log|diag" >&2; exit 2 ;;
esac

keys=/etc/agent-keys
work=/var/lib/agent-box
libexec=/usr/local/libexec/agent-box
repo=$work/checkouts/rebuild   # this wrapper's own checkout of central-hub
envdir=$work/rebuild-dev
inv_src=$keys/rebuild-dev/inventory
inventory=$envdir/inventory
nodekey=$keys/rebuild-node-key
export HOME=$work PATH=$libexec/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin
export TF_DATA_DIR=$work/tofu-data/rebuild-dev TF_IN_AUTOMATION=1
export ANSIBLE_COLLECTIONS_PATH=$libexec/collections ANSIBLE_HOME=$work/ansible-home

if [[ ${1:-} == diag && $# -eq 1 ]]; then
  [[ -f $inventory/hosts.yml ]] || { echo "rebuild: no dev inventory yet; run rebuild up first" >&2; exit 1; }
  diag_kc() {
    # Its own known_hosts file: a diag must never write host keys into the file a running rebuild uses.
    ansible 'k8s_control_plane[0]' -i "$inventory/" -b -m ansible.builtin.command \
      -e "ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$work/state/diag_known_hosts'" \
      -a "kubectl --kubeconfig /etc/kubernetes/admin.conf $*" 2>&1 | sed -E '1{/ \| (CHANGED|SUCCESS|FAILED)/d}' | cut -c1-300 || true   # one failing kubectl must not skip the sections after it (set -e, pipefail)
  }
  mkdir -p "$work/state"
  rm -f -- "$work/state/diag_known_hosts"   # the nodes' host keys change with every rebuild
  # Each dev VM's memory and CPU as Proxmox sees them, and the node's memory, with the dev token the run uses (GET
  # only, the token on curl's stdin), then each node's own memory, load and pressure, so a starved node is measured,
  # not guessed (the 3072 MiB control plane of 2026-11-18 06:11 UTC). A failed read prints one line and goes on.
  px_get() { # path after /api2/json
    # shellcheck source=/dev/null
    ( set -a; . "$keys/proxmox-dev.env"; set +a
      insecure=(); case "${PROXMOX_VE_INSECURE:-}" in true|1) insecure=(-k) ;; esac
      printf 'header = "Authorization: PVEAPIToken=%s"\n' "$PROXMOX_VE_API_TOKEN" |
        curl -sS --fail --max-time 30 "${insecure[@]}" -K - "${PROXMOX_VE_ENDPOINT%/}/api2/json/$1" ) 2>/dev/null
  }
  echo "== dev VMs on Proxmox (VM IDs 250-257: status, memory used of max, CPU)"
  vms=$(px_get 'cluster/resources?type=vm' || true)
  printf '%s' "$vms" | python3 -I -c 'import json,sys
for r in sorted(json.load(sys.stdin)["data"], key=lambda r: r.get("vmid", 0)):
    if 250 <= int(r.get("vmid", 0)) <= 257:
        print("vmid=%s status=%s mem=%s of %s MiB cpu=%.0f%% of %s vCPU" % (r.get("vmid"), r.get("status"),
              int(r.get("mem", 0)) // 1048576, int(r.get("maxmem", 0)) // 1048576, 100 * float(r.get("cpu", 0)), r.get("maxcpu")))' \
    || echo "(the guest list could not be read)"
  # How many dev VMs are running. With none, every section that reaches a node over ssh would only print a timeout, so
  # they are skipped with one line. If the guest list could not be read, the count is "unknown" and the sections run.
  running=$(printf '%s' "$vms" | python3 -I -c 'import json,sys
print(sum(1 for r in json.load(sys.stdin)["data"] if 250 <= int(r.get("vmid", 0)) <= 257 and r.get("status") == "running"))' 2>/dev/null || echo unknown)
  dnode=$(sed -n 's/^[[:space:]]*proxmox_node_name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$keys/dev-vms.tfvars" | head -1)
  px_get "nodes/$dnode/status" | python3 -I -c 'import json,sys
d = json.load(sys.stdin)["data"]
m, w = d.get("memory") or {}, d.get("swap") or {}
mib = lambda v: "?" if v is None else str(int(v) // 1048576)
print("node memory total %s used %s available %s MiB; swap used %s of %s MiB; cpu %.0f%%" % (mib(m.get("total")), mib(m.get("used")),
      mib(m.get("available")), mib(w.get("used")), mib(w.get("total")), 100 * float(d.get("cpu", 0))))' \
    || echo "(the node status could not be read)"
  if [[ $running == 0 ]]; then
    echo "dev nodes: none running (no running vmid 250-257); the node, Argo CD and pod sections are skipped"
  else
    echo "== each dev node: free -m, load average, memory and CPU pressure"
    ansible 'k8s_control_plane:k8s_workers' -i "$inventory/" -b -m ansible.builtin.shell \
      -e "ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$work/state/diag_known_hosts'" \
      -a 'free -m; cat /proc/loadavg; for f in memory cpu; do echo "$f: $(head -1 /proc/pressure/$f)"; done' 2>&1 | grep -v '^\[WARNING\]' | cut -c1-300 || true
  fi
  [[ $running != 0 ]] || exit 0   # no dev node to reach; the line above said so
  echo "== argocd applications"
  diag_kc -n argocd get applications.argoproj.io -o 'custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,HEALTH_MESSAGE:.status.health.message,CONDITIONS:.status.conditions[*].message'
  for ns in alerts monitoring; do
    echo "== newest events, namespace $ns"
    diag_kc -n "$ns" get events --sort-by=.lastTimestamp | tail -n 25
  done
  echo "== pods not Running or Completed, all namespaces"
  diag_kc get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed"'
  # Why: each application that is not Synced and Healthy with its messages and resources, and the last 30 log lines of each
  # pod in Error (at most 6), both scrubbed of secrets by hosts/diag-apps.py in the box's checkout of main.
  if [[ -f $repo/hosts/diag-apps.py ]]; then
    diag_json() {
      ansible 'k8s_control_plane[0]' -i "$inventory/" -b -m ansible.builtin.command \
        -e "ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$work/state/diag_known_hosts'" \
        -a "kubectl --kubeconfig /etc/kubernetes/admin.conf $*" 2>&1 | sed -E '1{/ \| (CHANGED|SUCCESS|FAILED)/d}' || true
    }
    echo "== applications not Synced and Healthy: messages and resources"
    diag_json -n argocd get applications.argoproj.io -o json | python3 -I "$repo/hosts/diag-apps.py" apps | cut -c1-300
    echo "== last 30 log lines of each pod in Error (at most 6 pods)"
    diag_json get pods -A --no-headers |
      awk '$4 ~ /^(Error|CrashLoopBackOff|OOMKilled|CreateContainerError|RunContainerError|Init:Error|Init:CrashLoopBackOff)$/ {print $1, $2}' | head -n 6 |
      while read -r pns pod; do
        echo "-- $pns/$pod"
        diag_json -n "$pns" logs "$pod" --tail=30 --all-containers=true | python3 -I "$repo/hosts/diag-apps.py" scrub
      done
  else
    echo "(hosts/diag-apps.py is not in the box's checkout of main yet; run rebuild up once)"
  fi
  echo "== monitoring pods and volume claims"
  diag_kc -n monitoring get pods -o wide
  diag_kc -n monitoring get pvc
  exit 0
fi

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
# One rebuild run at a time, in its own checkout: no other run, of this wrapper or another, can
# move the code under it. The lock is held until the run and everything it starts end.
exec 9>"$work/state/rebuild.lock"
flock -n 9 || { echo "rebuild: another rebuild run is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
echo "rebuild: central-hub $(git -C "$repo" rev-parse --short HEAD)"
# Rebuilt dev VMs get new SSH host keys, and the inventory's accept-new setting refuses a changed key.
# This file only holds keys learned from earlier dev runs, so each run starts without it (after the lock,
# so a refused second call can't delete it under a run that is going).
rm -f -- "$envdir/known_hosts"

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
# The values the dev cluster's ExternalSecrets read from namespace secret-source (ntfy's, runbook
# seed-secret-source.md), the box's own and made once with random values (dev only). Never printed.
ssfile=$keys/rebuild-secret-source.env
if [[ ! -s $ssfile ]]; then
  (umask 077
   {
     printf 'ntfy-owner-password=%s\n' "$(head -c 64 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 24)"
     printf 'ntfy-alertmanager-token=tk_%s\n' "$(head -c 128 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 29)"
     printf 'ntfy-proxmox-token=tk_%s\n' "$(head -c 128 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 29)"
   } > "$ssfile")
fi
# Dev's heartbeat URL (pick 213): Alertmanager mounts Secret alertmanager-heartbeat, so dev needs the
# line too, or its ExternalSecret never syncs and the apps stage waits forever. Never c1's real URL:
# dev's pings would keep c1's check up while c1 is down. An .invalid host never resolves (RFC 6761),
# so dev's heartbeat POST fails harmlessly. Added to a file made before this line existed, too.
if ! grep -q '^healthchecks-ping-url=' "$ssfile"; then
  (umask 077; printf '%s\n' 'healthchecks-ping-url=https://hc-ping.invalid/dev-not-a-check' >> "$ssfile")
fi
chmod 600 "$ssfile"
# The secrets store (proposed D-0038), dev only like this wrapper: once `secrets-store configure` has
# made the AppRole rebuild's IDs, stage openbao writes the rebuilt cluster's service-account key to
# the store (hosts/ansible/playbooks/k8s-openbao-auth.yml), so External Secrets can sign in there.
# The same values reach Argo CD's root Application (k8s_gitops_source_openbao_*), so the secret-store app
# adds store `openbao` and its one test ExternalSecret. Before that, both are left out and nothing changes.
stages="vms cluster storage restore gitops secrets apps gateway checks"
openbao_env=""
store_url=""
store_keys=$keys/dev
if [[ -s $store_keys/openbao-rebuild-role-id && -s $store_keys/openbao-rebuild-secret-id && -s $store_keys/secrets-store-ca.crt && -s $work/secrets-store.json ]]; then
  store_addr=$(python3 -I -c 'import ipaddress, json, sys; print(ipaddress.ip_address(json.load(open(sys.argv[1]))["address"]))' "$work/secrets-store.json") \
    || { echo "rebuild: the secrets store's address in $work/secrets-store.json is not an IP address" >&2; exit 1; }
  store_url=https://$store_addr
  stages="vms cluster storage restore gitops secrets openbao apps gateway checks"
  openbao_env="OPENBAO_ADDR=$store_url
OPENBAO_CACERT=$store_keys/secrets-store-ca.crt
OPENBAO_ROLE_ID_FILE=$store_keys/openbao-rebuild-role-id
OPENBAO_SECRET_ID_FILE=$store_keys/openbao-rebuild-secret-id"
fi
# The secrets store inside the dev cluster (D-0058, dev first), switched on by the one-line file the agent_box role
# writes (agent_box_openbao_in_cluster). The root chart then makes the apps openbao-store and openbao, with the seal
# key's volume on the first k8s_workers host, and stage openbao-seal puts the key there first.
# This wrapper keeps the key as its SOPS copy (D-0058 rules 3 and 9), encrypted to the box's own age identity,
# which the agent_box role makes with the secrets bundle (agent_box_secrets_bundle); without that identity this refuses.
# This run writes no plain copy to disk. A plain openbao-seal.key from the store VM's wrapper (secrets-store.sh), if
# one exists, stays until it is removed, which is a delete and the owner's tap (D-0042 rule 6).
# The copy is made here once, from the store VM's key file when one exists or else from 32 random bytes, and is never
# replaced: a new key would make every snapshot unreadable. Each run decrypts it to a file in memory (/dev/shm) that
# only this user can read and that is removed when the run ends. The keys folder is in the box's daily bundle, so the
# copy leaves the box only once the bundle's off-box send is installed (agent_box_opnsense_offbox set and
# agent_box_secrets_bundle.offbox true, tasks/secrets_bundle.yml); until then
# the dev key is only on the box and the node. Dev's key needs no tap (D-0058 rule 3). The VM store's wiring above
# and this are never on together.
in_cluster=false
seal_env=""
seal_tmp=""
if [[ -f $work/openbao-in-cluster && $(tr -d '[:space:]' < "$work/openbao-in-cluster") == true ]]; then
  [[ -z $store_url ]] || { echo "rebuild: the store VM's wiring and the store inside the cluster are both set; refusing" >&2; exit 1; }
  in_cluster=true
  identity=$keys/secrets-bundle/age-identity.txt
  [[ -s $identity ]] || { echo "rebuild: $identity is missing; set agent_box_secrets_bundle and run the agent_box role, so the seal key can be kept as a SOPS copy" >&2; exit 1; }
  seal_sops=$store_keys/openbao-seal.key.sops.json
  # A run killed outright (SIGKILL) leaves its folder; the run lock above means no other run's folder is live now.
  find /dev/shm -maxdepth 1 -name 'rebuild-seal.*' -user "$(id -u)" -exec rm -rf -- {} +
  seal_tmp=$(mktemp -d /dev/shm/rebuild-seal.XXXXXX) || { echo "rebuild: no private folder in /dev/shm for the seal key" >&2; exit 1; }
  trap 'rm -rf -- "$seal_tmp"' EXIT
  trap 'exit 1' INT TERM HUP
  mkdir -p "$store_keys"
  if [[ ! -e $seal_sops ]]; then
    if [[ -f $store_keys/openbao-seal.key ]]; then cp -- "$store_keys/openbao-seal.key" "$seal_tmp/new.key"
    else openssl rand -out "$seal_tmp/new.key" 32; fi
    [[ $(wc -c < "$seal_tmp/new.key") -eq 32 ]] || { echo "rebuild: the seal key to keep is not 32 bytes" >&2; exit 1; }
    recipient=$("$libexec/age-keygen" -y "$identity")
    [[ $recipient =~ ^age1[0-9a-z]{58}$ ]] || { echo "rebuild: the box's identity gives no age recipient" >&2; exit 1; }
    "$libexec/sops" encrypt --input-type binary --output-type json --age "$recipient" \
      --output "$seal_sops.part" "$seal_tmp/new.key" || { rm -f -- "$seal_sops.part"; echo "rebuild: sops could not encrypt the seal key" >&2; exit 1; }
    if ! SOPS_AGE_KEY_FILE=$identity "$libexec/sops" decrypt --input-type json --output-type binary \
         --output "$seal_tmp/back.key" "$seal_sops.part" || ! cmp -s "$seal_tmp/back.key" "$seal_tmp/new.key"; then
      rm -f -- "$seal_sops.part"; echo "rebuild: the seal key's SOPS copy does not read back to the same bytes" >&2; exit 1
    fi
    mv -- "$seal_sops.part" "$seal_sops"
    rm -f -- "$seal_tmp/new.key" "$seal_tmp/back.key"
  fi
  SOPS_AGE_KEY_FILE=$identity "$libexec/sops" decrypt --input-type json --output-type binary \
    --output "$seal_tmp/openbao-seal.key" "$seal_sops" || { echo "rebuild: $seal_sops does not decrypt with the box's identity" >&2; exit 1; }
  [[ $(wc -c < "$seal_tmp/openbao-seal.key") -eq 32 ]] || { echo "rebuild: the seal key in $seal_sops is not 32 bytes" >&2; exit 1; }
  stages="vms cluster storage openbao-seal restore gitops secrets apps gateway checks"
  # The admin AppRole's IDs, which stage openbao-handover hands the store's admin login over to (D-0038 rule 6).
  # Made here when missing, by the same rule as secrets-store.sh (both run as this user): never replaced, no
  # trailing newline, never printed.
  [[ -f $store_keys/openbao-admin-role-id ]] || openssl rand -hex 24 | tr -d '\n' > "$store_keys/openbao-admin-role-id"
  [[ -f $store_keys/openbao-admin-secret-id ]] || openssl rand -hex 24 | tr -d '\n' > "$store_keys/openbao-admin-secret-id"
  seal_env="OPENBAO_SEAL_KEY_FILE=$seal_tmp/openbao-seal.key
OPENBAO_ADMIN_ROLE_ID_FILE=$store_keys/openbao-admin-role-id
OPENBAO_ADMIN_SECRET_ID_FILE=$store_keys/openbao-admin-secret-id"
  # The rebuild hold (DESIGN section 6): a run that leaves a fresh, empty store (rebuild and teardown, or up while
  # no dev VM is in the state, as after an ephemeral-dev run), while this box holds snapshots of an earlier store,
  # writes the hold first. secrets-store's snapshot and restore, and the hourly off-box send, then wait until
  # restore-rebuilt brings the newest snapshot back (the owner's tap, D-0058 rule 7) or clear-hold sets the earlier
  # snapshots aside. With no snapshot on the box there is nothing to keep, so no hold.
  dev_vms=$(python3 -I -c '
import json, sys
try:
    s = json.load(open(sys.argv[1]))
except FileNotFoundError:
    print(0); sys.exit()
print(sum(len(r.get("instances", [])) for r in s.get("resources", [])
          if r.get("type") == "proxmox_virtual_environment_vm" and r.get("mode") == "managed"))' "$work/state/dev-vms.tfstate") ||
    { echo "rebuild: the dev state at $work/state/dev-vms.tfstate could not be read" >&2; exit 1; }
  fresh=false
  [[ ${extra[*]} == *teardown* ]] && fresh=true
  [[ $action == up && $dev_vms == 0 ]] && fresh=true
  if [[ $fresh == true ]] && compgen -G "$store_keys/openbao-snapshots/raft-*.snap" >/dev/null; then
    [[ -e $work/state/secrets-store.rebuilding ]] || date -u +%FT%TZ > "$work/state/secrets-store.rebuilding"
    echo "rebuild: the secrets store's rebuild hold is set; after the run, restore-rebuilt (the owner's tap) or clear-hold"
  fi
fi
# What a dev run does on a node short of memory is the owner's pick, never a default (rebuild-k8s.sh,
# docs/runbooks/rebuild-k8s-layer-with-one-command.md): ephemeral-dev or keep-dev, from the one-line file the
# agent_box role writes (agent_box_short_node). Anything else, or no file, leaves the setting out, and the dev
# run then refuses on a short node before it stops anything.
short_node=""
if [[ -f $work/short-node ]]; then
  short_node=$(tr -d '[:space:]' < "$work/short-node")
  case $short_node in
    ephemeral-dev|keep-dev) ;;
    *) echo "rebuild: $work/short-node holds a value other than ephemeral-dev or keep-dev; ignoring it" >&2; short_node="" ;;
  esac
fi
short_node_env=""
[[ -z $short_node ]] || short_node_env="PREFLIGHT_SHORT_NODE=$short_node"
# A copy of the tfvars whose node key is the box's own, so the nodes accept the box.
# The agents' token clones into pool dev, whose ACL survives a teardown, and clones only template 9001, the copy of template 9000 on VNet dev
# (hosts/terraform/home/bootstrap/agent-access.sh); the Mac's tfvars name 9000, for its root token.
awk -v pub="$pub" '/^[[:space:]]*node_ssh_public_key[[:space:]]*=/ { print "node_ssh_public_key = \"" pub "\""; next }
  /^[[:space:]]*(template_vm_id|pool_id)[[:space:]]*=/ { next } { print }' "$keys/dev-vms.tfvars" > "$envdir/dev-vms.tfvars"
printf '%s\n' 'template_vm_id = 9001' 'pool_id = "dev"' >> "$envdir/dev-vms.tfvars"
grep -q '^node_ssh_public_key = "ssh-ed25519 ' "$envdir/dev-vms.tfvars" || { echo "rebuild: dev-vms.tfvars has no node_ssh_public_key line to set" >&2; exit 1; }
rm -rf "$inventory"
install -d -m 700 "$inventory"
python3 -I -c "$(cat <<'PY'
import ipaddress, json, os, sys, yaml
src, dst, key, known, keys, store_url, store_ca, in_cluster, store_settings = sys.argv[1:10]
d = yaml.safe_load(open(src))
# The box's own address as a /32, for the hand-over (the box's path to the store): the settings' box_cidr, private,
# empty until that path is set. Checked as openbao-prod.sh checks prod's.
box_cidr = ""
if in_cluster == "true" and os.path.isfile(store_settings):
    box_cidr = json.load(open(store_settings)).get("box_cidr") or ""
if box_cidr:
    try: n = ipaddress.ip_network(box_cidr, strict=False)
    except ValueError: n = None
    if n is None or n.version != 4 or n.prefixlen != 32 or n.is_loopback:
        print("rebuild: box_cidr in the secrets store's settings must be one IPv4 address as a /32, not loopback", file=sys.stderr); sys.exit(1)
# The store's admin address (D-0062), private: one address of dev's load-balancer pool, on which OpenBao sees the box's
# own address. It needs box_cidr, the one source its NetworkPolicy lets in.
admin = ""
if in_cluster == "true" and os.path.isfile(store_settings):
    admin = json.load(open(store_settings)).get("admin_address") or ""
if admin:
    try: a = ipaddress.ip_address(admin)
    except ValueError: a = None
    if a is None or a.version != 4 or a.is_loopback or not box_cidr:
        print("rebuild: admin_address in the secrets store's settings must be one IPv4 address, not loopback, with box_cidr set", file=sys.stderr); sys.exit(1)
DROP = {"ansible_ssh_common_args", "ansible_ssh_extra_args", "ansible_ssh_args", "ansible_ssh_private_key_file",
        "ansible_ssh_host", "ansible_ssh_executable", "ansible_connection", "ansible_ssh_pass", "ansible_password",
        "ansible_private_key_file", "ansible_host_key_checking",
        "k8s_gateway_smoke_client", "k8s_certs_smoke_client", "k8s_certs_smoke_root_file",
        "k8s_backup_env_file", "k8s_backup_azure_fixed_cert_file", "k8s_control_plane_encryption_key_file",
        "k8s_gitops_source_openbao_address", "k8s_gitops_source_openbao_ca_file",
        "k8s_gitops_source_openbao_in_cluster", "k8s_gitops_source_openbao_seal_node", "k8s_gitops_source_openbao_box_cidr",
        "k8s_gitops_source_openbao_admin_address"}
def walk(n):
    if isinstance(n, dict):
        for k in list(n):
            if k in DROP: del n[k]
            elif k == "proxmox" and isinstance(n[k], dict) and ("hosts" in n[k] or "children" in n[k] or "vars" in n[k]): del n[k]
            else: walk(n[k])
    elif isinstance(n, list):
        for i in n: walk(i)
walk(d)
def value(n, name):
    if isinstance(n, dict):
        if name in n and isinstance(n[name], str): return n[name]
        for x in n.values():
            r = value(x, name)
            if r is not None: return r
    return None
# No admin_address in the settings: dev picks its own, so dev renders the admin path with no hand step (D-0062; the
# owner's ask to rebuild from code with no hand steps). It is the highest address of dev's load-balancer pool below
# the pool's last, other than dev's Gateway address, from the dev inventory's own values only (the role's default
# pool is prod's). The address is private, so it is never printed. A settings value still wins.
if in_cluster == "true" and box_cidr and not admin:
    pool = value(d, "k8s_control_plane_lb_cidr")
    gw = value(d, "k8s_gitops_source_gateway_address") or ""
    if pool:
        try: net = ipaddress.ip_network(pool, strict=True)
        except ValueError: net = None
        if net is None or net.version != 4 or net.num_addresses < 4:
            print("rebuild: k8s_control_plane_lb_cidr in the dev inventory must be one IPv4 network of 4 addresses or more", file=sys.stderr); sys.exit(1)
        for i in range(int(net.broadcast_address) - 1, int(net.network_address), -1):
            if str(ipaddress.ip_address(i)) != gw:
                admin = str(ipaddress.ip_address(i))
                break
        print("rebuild: admin_address: none in the settings, so dev's own pick from its load-balancer pool", file=sys.stderr)
if in_cluster == "true" and not box_cidr:
    # The admin address needs the box's /32, the one source its NetworkPolicy lets in, and box_cidr is set only from
    # the controller (agent_box_secrets_store in the private inventory). Not a stop: dev is built without the path.
    print("rebuild: no admin address: box_cidr is not in the secrets store's settings; set it from the controller (agent_box_secrets_store)", file=sys.stderr)
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
if store_url:
    v["k8s_gitops_source_openbao_address"] = store_url
    v["k8s_gitops_source_openbao_ca_file"] = store_ca
if in_cluster == "true":
    # The seal key's node: the first worker, which the openbao-seal stage writes the key to. Its inventory name is
    # its Kubernetes node name (STD-0001 hostnames); the stage checks that against the node's address and refuses
    # if they differ. The box's /32 goes to the hand-over only once its settings have box_cidr (the box's path to the store).
    w = find(d, "k8s_workers")
    hosts = list((w or {}).get("hosts") or {})
    if not hosts:
        print("rebuild: the dev inventory has no k8s_workers host for the seal key", file=sys.stderr); sys.exit(1)
    v["k8s_gitops_source_openbao_in_cluster"] = True
    v["k8s_gitops_source_openbao_seal_node"] = hosts[0]
    if box_cidr: v["k8s_gitops_source_openbao_box_cidr"] = box_cidr
    if admin: v["k8s_gitops_source_openbao_admin_address"] = admin
yaml.safe_dump(d, open(dst, "w"), default_flow_style=False)
PY
)" "$inv_src/hosts.yml" "$inventory/hosts.yml" "$nodekey" "$envdir/known_hosts" "$keys" "$store_url" "$store_keys/secrets-store-ca.crt" "$in_cluster" "$work/secrets-store.json"
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
STAGES="$stages"
SECRET_SOURCE_FILE=$ssfile
$openbao_env
$seal_env
$short_node_env
RESTORE_HOOK='cd "\$REPO/hosts/ansible" && ansible-playbook -i "\$INVENTORY" playbooks/k8s-restore.yml'
RESTORE_CHECK_HOOK='cd "\$REPO/hosts/ansible" && ansible-playbook -i "\$INVENTORY" playbooks/k8s-restore.yml --tags restore_check'
ENV
chmod 600 "$envdir/rebuild.env"

# With the seal key in memory, the run is a child, so the key's folder is removed when it ends; otherwise exec.
if [[ -n $seal_tmp ]]; then
  bash "$repo/hosts/rebuild-k8s.sh" "$envdir" "${extra[@]}"
else
  exec bash "$repo/hosts/rebuild-k8s.sh" "$envdir" "${extra[@]}"
fi
