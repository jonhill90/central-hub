#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store.sh: build and set up the lab's secrets store, OpenBao,
# on dev (docs/runbooks/set-up-the-secrets-store.md, proposed D-0038). It runs as user `keys` through
# sudo, so the session that asks for it never sees the Proxmox token, the seal key, the AppRole IDs,
# the recovery shares or the VM's SSH key. Installed by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/secrets-store.sh plan|apply|configure|recovery|status|snapshot|restore|restore-rebuilt [raft-<time>.snap]|clear-hold|destroy
# plan, apply, destroy: OpenTofu on hosts/terraform/home/secrets-store with the agents' Proxmox token.
# configure: the openbao playbook over SSH, with the owner's sign-in once the dev rebuild has handed over
# Keycloak's issuer (pick 233). recovery: makes the recovery shares once (self-
# initialization makes none) into the keys folder, records their time and takes a snapshot that holds them.
# status: sys/health, which holds no secret. snapshot: writes kv/dev/snapshot-mark (one key, its own time, no
# secret), then copies a Raft snapshot off the store into the keys folder, with the store's cluster ID beside it.
# restore: puts the newest snapshot of the same cluster back, never forced, and proves it by the mark (D-0038
# Confirmations 4 and 7, pick 239). restore-rebuilt: after a destroy and rebuild, puts back the newest snapshot
# of the store's previous cluster, forced only if OpenBao refuses it for the keys (Confirmation 5, pick 238).
# Both refuse a snapshot older than the recovery shares. destroy leaves a hold that stops the hourly off-box send
# until restore-rebuilt passes; clear-hold sets the earlier store's snapshots aside in a kept folder that rotation
# never reads, then removes it, when the rebuilt store is to stay as it is. Dev only: every
# action refuses a store outside 550-599.
set -euo pipefail
umask 077

usage() { echo "usage: secrets-store plan|apply|configure|recovery|status|snapshot|restore|restore-rebuilt [raft-<time>.snap]|clear-hold|destroy" >&2; exit 2; }
named=''
case ${1:-} in
  plan | apply | configure | recovery | status | snapshot | restore | clear-hold | destroy) action=$1; [[ $# -eq 1 ]] || usage ;;
  # restore-rebuilt may name one snapshot file exactly, e.g. one moved back from the kept folder (pick 239).
  restore-rebuilt)
    action=$1
    [[ $# -le 2 ]] || usage
    named=${2:-}
    [[ -z $named || $named =~ ^raft-[0-9]{8}T[0-9]{6}Z\.snap$ ]] || { echo "secrets-store: a snapshot is named raft-<YYYYMMDDTHHMMSSZ>.snap" >&2; exit 2; }
    ;;
  *) usage ;;
esac

keys=/etc/agent-keys
env_keys=$keys/dev   # dev only; prod follows D-0035 rule 3 with its own folder
work=/var/lib/agent-box
repo=$work/checkouts/secrets-store   # this wrapper's own checkout of central-hub
folder=$repo/hosts/terraform/home/secrets-store
settings=$work/secrets-store.json   # private values the agent_box role writes from the inventory
state=$work/state/secrets-store.tfstate
plan=$work/state/secrets-store.tfplan
vars=$work/state/secrets-store.tfvars.json
sshkey=$env_keys/secrets-store-ssh
cacert=$env_keys/secrets-store-ca.crt
snapshots=$env_keys/openbao-snapshots   # the store's Raft snapshots, readable only with the seal key
snapshot_keep=24
# An earlier store's snapshots that clear-hold set aside: rotation never reads this folder, so they stay until
# the owner taps their removal (a delete under D-0042 rule 6).
kept=$env_keys/openbao-snapshots-kept
hold=$work/state/secrets-store.rebuilding   # from destroy until restore-rebuilt passes; the off-box send skips meanwhile
# The owner's sign-in (agent pick 233), dev: the dev rebuild's identity stage writes Keycloak's issuer, its
# Gateway's address and the dev CA's root here once the store's address is in the realm; its values file holds
# the client secret and the dev users' passwords and seeds. Absent: configure sets no sign-in.
oidc_handoff=$work/rebuild-dev/openbao-oidc.json
identity_values=$work/rebuild-dev/identity.env
export HOME=$work PATH=/usr/local/libexec/agent-box/ansible-venv/bin:/usr/local/bin:/usr/bin:/bin
export TF_DATA_DIR=$work/tofu-data/secrets-store TF_IN_AUTOMATION=1 ANSIBLE_COLLECTIONS_PATH=/usr/local/libexec/agent-box/collections ANSIBLE_HOME=$work/ansible-home

[[ -f $settings ]] || { echo "secrets-store: $settings is missing; set agent_box_secrets_store in the inventory and run the agent_box role" >&2; exit 1; }
setting() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$settings" "$1"; }

# Dev only. The store's IDs are 500-599 (agent pick 226, under STD-0001's next-free-hundred rule); dev
# is 550-599, as dev is 250-257 among 200-299. A prod store gets its own wrapper and keys folder after
# dev passes (D-0035 rule 3), and its recovery shares go only to the owner's Mac (D-0038 rule 5).
vm_id=$(setting vm_id)
[[ $vm_id =~ ^5[5-9][0-9]$ ]] || { echo "secrets-store: VM ID $vm_id is not a dev store ID (550-599); refused" >&2; exit 1; }

# Only reviewed code on main runs with the keys, never a checkout a session can edit. One run at a time.
exec 9>"$work/state/secrets-store.lock"
flock -n 9 || { echo "secrets-store: another secrets-store run is going; try again when it ends" >&2; exit 1; }
[[ -d $repo/.git ]] || git clone --quiet --no-checkout "$(git -C "$work/central-hub" remote get-url origin)" "$repo"
git -C "$repo" fetch --quiet origin main
git -C "$repo" checkout --quiet --detach origin/main
echo "secrets-store: central-hub $(git -C "$repo" rev-parse --short HEAD)"

# The store's keys, made here the first time and never printed: the VM's SSH key, the 32-byte static
# seal key (D-0038 rule 4) and the admin AppRole's IDs (rule 6). A file that exists is never replaced:
# a new seal key would make every snapshot unreadable. The IDs carry no trailing newline, because
# the store's first start reads each file whole.
mkdir -p "$env_keys"
[[ -f $sshkey ]] || ssh-keygen -q -t ed25519 -N "" -C "keys@agent-box secrets-store" -f "$sshkey"
[[ -f $env_keys/openbao-seal.key ]] || openssl rand -out "$env_keys/openbao-seal.key" 32
[[ -f $env_keys/openbao-admin-role-id ]] || openssl rand -hex 24 | tr -d '\n' > "$env_keys/openbao-admin-role-id"
[[ -f $env_keys/openbao-admin-secret-id ]] || openssl rand -hex 24 | tr -d '\n' > "$env_keys/openbao-admin-secret-id"

tofu_run() {
  python3 -I - "$settings" "$sshkey.pub" "$repo" "$vars" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
json.dump({
    "proxmox_node_name": s["proxmox_node_name"],
    "vnet": s["vnet"],
    "vlans_file": sys.argv[3] + "/hosts/ansible/inventories/home/group_vars/all/vlans.yml",
    "template_vm_id": s["template_vm_id"],
    "ssh_public_key": open(sys.argv[2]).read().strip(),
    "store": {k: s[k] for k in ("name", "vm_id", "address", "cores", "memory_mb", "disk_gb")},
}, open(sys.argv[4], "w"))
PY
  # PROXMOX_VE_ENDPOINT and PROXMOX_VE_API_TOKEN (agent@pve!dev).
  set -a
  # shellcheck source=/dev/null
  . "$keys/proxmox-dev.env"
  set +a
  tofu() { /usr/local/bin/tofu -chdir="$folder" "$@"; }
  tofu init -input=false -backend-config="path=$state" >/dev/null
  case $action in
    plan) tofu plan -input=false -var-file="$vars" -out="$plan" ;;
    apply)
      [[ -f $plan ]] || { echo "secrets-store: no saved plan; run secrets-store plan first" >&2; exit 1; }
      tofu apply -input=false "$plan"
      rm -f "$plan"
      ;;
    destroy)
      date -u +%FT%TZ > "$hold"
      tofu plan -destroy -input=false -var-file="$vars" -out="$plan"
      tofu apply -input=false "$plan"
      rm -f "$plan"
      ;;
  esac
}

configure() {
  local extra inventory
  extra=$(mktemp --suffix=.json "$work/state/secrets-store-extra.XXXXXX")
  inventory=$(mktemp --suffix=.json "$work/state/secrets-store-inventory.XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -f '$extra' '$inventory'" EXIT
  python3 -I - "$settings" "$inventory" "$extra" "$env_keys" "$cacert" "$oidc_handoff" "$identity_values" "$work/state" <<'PY'
import json, os, sys
s = json.load(open(sys.argv[1]))
k = sys.argv[4]
handoff, values, state = sys.argv[6], sys.argv[7], sys.argv[8]
json.dump({"openbao": {"hosts": {"openbao_vm": {
    "ansible_host": s["address"], "ansible_user": s.get("admin_user", "admin")}}}}, open(sys.argv[2], "w"))
extra = {
    "openbao_hostname": s["name"],
    "openbao_address": s["address"],
    "openbao_box_address": s["box_address"],
    "openbao_seal_key_id": str(s.get("seal_key_id", "1")),
    "openbao_seal_key_src": k + "/openbao-seal.key",
    "openbao_admin_role_id_src": k + "/openbao-admin-role-id",
    "openbao_admin_secret_id_src": k + "/openbao-admin-secret-id",
    "openbao_cacert_dest": sys.argv[5],
}
if os.path.isfile(handoff) and os.path.isfile(values):
    o = json.load(open(handoff))
    ca = state + "/openbao-oidc-ca.pem"   # the dev CA's public root, not a secret
    with open(ca, "w") as f:
        f.write(o["ca_pem"])
    extra["openbao_oidc"] = {"discovery_url": o["discovery_url"], "values_file": values, "ui_names": [s["address"]],
                             "ca_pem_file": ca, "pin_address": o["gateway_address"], "owner_user": "dev-admin"}
    extra["openbao_oidc_proof"] = {"admin_user": "dev-admin", "viewer_user": "dev-viewer", "other_admin_user": "dev-admin2",
                                   "gateway_address": o["gateway_address"], "verify": False}
json.dump(extra, open(sys.argv[3], "w"))
PY
  mkdir -p "$work/.ssh"
  cd "$repo/hosts/ansible"
  ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$work/.ssh/known_hosts" \
    ansible-playbook -i "$inventory" --private-key "$sshkey" -e "@$extra" playbooks/openbao.yml
}

addr() { echo "https://$(setting address)"; }

status() {
  curl -sS --fail-with-body --cacert "$cacert" "$(addr)/v1/sys/health"
  echo
}

# An admin token for one call. The secret ID goes to curl on stdin, never as an argument.
admin_token() {
  python3 -I -c 'import json,sys; print(json.dumps({"role_id": open(sys.argv[1]).read().strip(), "secret_id": open(sys.argv[2]).read().strip()}))' \
    "$env_keys/openbao-admin-role-id" "$env_keys/openbao-admin-secret-id" |
    curl -sS --fail-with-body --cacert "$cacert" -X POST --data @- "$(addr)/v1/auth/approle/login" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["auth"]["client_token"])'
}

recovery() {
  local out=$env_keys/openbao-recovery.json made=$env_keys/openbao-recovery.made token stamp
  # Shares on the box are for dev only (D-0038 rule 5); checked again here, not only at the top.
  [[ $vm_id =~ ^5[5-9][0-9]$ ]] || { echo "secrets-store: recovery shares are made on the box for dev stores only; refused" >&2; exit 1; }
  [[ ! -s $out ]] || { echo "secrets-store: recovery shares exist already ($out); nothing done" >&2; exit 1; }
  # The follow-up snapshot below refuses during a rebuild, so refuse before any share is made (pick 239).
  [[ ! -e $hold ]] || { echo "secrets-store: a rebuild is in progress ($hold); run restore-rebuilt first; no shares made" >&2; exit 1; }
  # The shares' time, taken before they are asked for: a snapshot must be strictly later to be restored.
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  token=$(admin_token)
  # 3 shares, any 2 make a root token for break-glass (D-0038 rule 5). Written only to the keys folder.
  printf 'header = "X-Vault-Token: %s"\n' "$token" |
    curl -sS --fail-with-body --cacert "$cacert" -K - -X POST \
      --data '{"secret_shares":3,"secret_threshold":2}' "$(addr)/v1/sys/rotate/recovery/init" > "$out.part"
  python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d.get("keys") or d.get("data",{}).get("keys"), "no shares in the reply"' "$out.part" ||
    { echo "secrets-store: the reply held no recovery shares; kept at $out.part for checking" >&2; exit 1; }
  mv "$out.part" "$out"
  echo "$stamp" > "$made"
  printf 'header = "X-Vault-Token: %s"\n' "$token" |
    curl -sS --cacert "$cacert" -K - -X POST "$(addr)/v1/auth/token/revoke-self" >/dev/null
  echo "secrets-store: recovery shares written to the keys folder (not printed)"
  # Every snapshot from before now is refused by restore, so take one that holds the shares, in a later second.
  sleep 1
  ( snapshot ) || { echo "secrets-store: the shares are made, but the snapshot after them failed; until one succeeds, no snapshot can be restored; run secrets-store snapshot" >&2; exit 1; }
}

# Copy one Raft snapshot off the store, through the admin AppRole. Fails loudly: never an empty file.
snapshot() {
  # During a rebuild the store is empty: a snapshot now would write its mark into the fresh store, which
  # restore-rebuilt's empty-store guard would then refuse, and it would be a snapshot of nothing.
  [[ ! -e $hold ]] || { echo "secrets-store: a rebuild is in progress ($hold); run restore-rebuilt first" >&2; exit 1; }
  # Through AppRole snapshot-box, not the admin (D-0038 rules 8 and 12, agent pick 240).
  "$(dirname "$0")/secrets-store-snapshots.sh" take "$(addr)" "$cacert" "$env_keys" "$snapshots" "$snapshot_keep" dev
}

# Put the newest snapshot of this store's own cluster back, never forced, and prove it by the mark, under the
# guards in secrets-store-restore.sh (mode same).
restore() {
  [[ ! -e $hold ]] || { echo "secrets-store: a rebuild is in progress ($hold); use restore-rebuilt" >&2; exit 1; }
  "$(dirname "$0")/secrets-store-restore.sh" same "$(addr)" "$cacert" "$env_keys" "$snapshots" "$hold" 120
}

# After destroy, apply and configure: the newest snapshot of the store's previous cluster, under the guards in
# secrets-store-restore.sh (mode rebuilt). It removes the hold once its proof passes.
restore_rebuilt() {
  "$(dirname "$0")/secrets-store-restore.sh" rebuilt "$(addr)" "$cacert" "$env_keys" "$snapshots" "$hold" 120 "$named"
}

# The rebuilt store is to stay as it is, with no restore. The hold is what keeps rotation from removing the earlier
# store's snapshots, so first every snapshot not of the current cluster moves into the kept folder, which rotation
# never reads; then the hold goes, and snapshots and the hourly off-box send run again. Nothing is deleted.
clear_hold() {
  local cluster moved
  [[ -e $hold ]] || { echo "secrets-store: no rebuild hold; nothing done"; return 0; }
  # Only a store that answers 200 (initialized, unsealed, active): a sealed store's 503 body also holds an ID.
  [[ $(curl -s -o /dev/null -w '%{http_code}' --cacert "$cacert" "$(addr)/v1/sys/health" || true) == 200 ]] ||
    { echo "secrets-store: the store does not answer sys/health 200; the hold stays" >&2; exit 1; }
  cluster=$(curl -s --cacert "$cacert" "$(addr)/v1/sys/health" |
    python3 -I -c 'import json, sys; print(json.load(sys.stdin)["cluster_id"])') ||
    { echo "secrets-store: the store gave no cluster ID in sys/health; the hold stays" >&2; exit 1; }
  [[ -n $cluster ]] || { echo "secrets-store: empty cluster ID; the hold stays" >&2; exit 1; }
  moved=$("$(dirname "$0")/secrets-store-snapshots.sh" keep "$snapshots" "$kept" "$cluster") ||
    { echo "secrets-store: setting the earlier snapshots aside failed; the hold stays" >&2; exit 1; }
  rm -f -- "$hold"
  echo "secrets-store: rebuild hold removed; $moved earlier snapshot(s) set aside in $kept, not restored; removing them is the owner's tap"
}

case $action in
  configure) configure ;;
  status) status ;;
  recovery) recovery ;;
  snapshot) snapshot ;;
  restore) restore ;;
  restore-rebuilt) restore_rebuilt ;;
  clear-hold) clear_hold ;;
  *) tofu_run ;;
esac
