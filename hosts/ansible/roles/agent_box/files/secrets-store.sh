#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store.sh: the agent box's calls to the lab's secrets store, OpenBao,
# on dev, and with --prod on prod (docs/runbooks/set-up-the-secrets-store.md, D-0038 as D-0058 changes it). It runs as user `keys`
# through sudo, so the session that asks for it never sees the AppRole IDs or the recovery shares. Installed
# by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/secrets-store.sh recovery|status|snapshot|restore|restore-rebuilt [raft-<time>.snap]|clear-hold
#   sudo -n -u keys /usr/local/libexec/agent-box/secrets-store.sh put c1/<path> <key> < value   |   compare   |   reseed
#   sudo -n -u keys /usr/local/libexec/agent-box/secrets-store-prod.sh <the same actions>   (passes --prod first)
# The store runs inside the dev cluster and initialises itself (D-0058); the dev rebuild's stage openbao-handover
# gives its admin login the IDs this wrapper keeps. Every call goes to the store's address in the settings below, and
# is checked against the CA file beside the keys; the box's path to the store sets both (the Gateway PR). Until then
# each call that signs in stops with the missing value named. recovery: makes the recovery shares once (self-
# initialization makes none) into the keys folder, records their time and takes a snapshot that holds them.
# status: sys/health, which holds no secret. snapshot: writes kv/<env>/snapshot-mark (one key, its own time, no
# secret), then copies a Raft snapshot off the store into the keys folder, with the store's cluster ID beside it.
# restore: puts the newest snapshot of the same cluster back, never forced, and proves it by the mark (D-0038
# Confirmations 4 and 7, pick 239). restore-rebuilt: after a rebuild of the store, puts back the newest snapshot
# of the store's previous cluster, forced only if OpenBao refuses it for the keys (Confirmation 5, pick 238).
# Both refuse a snapshot older than the recovery shares. A rebuild leaves a hold that stops the hourly off-box send
# until restore-rebuilt passes; clear-hold sets the earlier store's snapshots aside in a kept folder that rotation
# never reads, then removes it, when the rebuilt store is to stay as it is. The rebuild wrapper writes the hold
# before a run that leaves a fresh store. put, compare and reseed keep SOPS's copy of every secret (D-0058 rule 8,
# secrets-store-kv.sh): put writes one key to SOPS, then to the store; compare names every key that differs; reseed
# fills a fresh store from SOPS, then takes a snapshot; put, put-apps and reseed write nothing during a rebuild hold.
# put-apps writes every value the apps read; the dev rebuild's stage app-secrets runs it, then compare, once the box's
# rebuild wrapper finds the gate open (sops_copies, box_cidr, the CA file, no hold). All of them refuse until the settings' sops_copies is true
# (the owner's access-right tap, D-0058 rule 9). One store per run (D-0058 rule 10): every action refuses unless the
# store's address is the c1 store of its own environment, as that environment's inventory names it. --prod uses the
# prod keys folder, settings and inventory, and makes no recovery shares (D-0038 rule 5: prod gets none).
set -euo pipefail
umask 077

usage() { echo "usage: secrets-store recovery|status|snapshot|restore|restore-rebuilt [raft-<time>.snap]|clear-hold|put c1/<path> <key>|put-apps|compare|reseed|owner-login owner|test|check-test|remove-test|plan|ssh-ca plan|apply|check|public <folder>|sign-host <key> <names> <out>" >&2; exit 2; }
named='' kv_path='' kv_key='' ssh_args=()
env=dev
if [[ ${1:-} == --prod ]]; then env=prod; shift; fi
case ${1:-} in
  recovery | status | snapshot | restore | clear-hold | put-apps | compare | reseed) action=$1; [[ $# -eq 1 ]] || usage ;;
  # The owner's sign-in to the store's page (secrets-store-owner.sh): prod only.
  owner-login)
    action=$1
    [[ $# -eq 2 && $2 =~ ^(owner|test|check-test|remove-test|plan)$ ]] || usage
    named=$2
    [[ $env == prod ]] || { echo "secrets-store: owner-login is for the prod store only; refused" >&2; exit 1; }
    ;;
  # The SSH certificate sign-in for the lab's Linux boxes (secrets-store-ssh.sh, D-0064).
  ssh-ca)
    action=$1
    [[ $# -ge 2 && $2 =~ ^(plan|apply|check|public|sign-host)$ ]] || usage
    named=$2; shift 2; ssh_args=("$@")
    ;;
  # The value comes on stdin, never as an argument; the helper checks the path and key again.
  put)
    action=$1
    [[ $# -eq 3 ]] || usage
    kv_path=$2 kv_key=$3
    [[ $kv_path =~ ^c1(/[a-z0-9][a-z0-9_-]*)+$ ]] || { echo "secrets-store: the path is c1/<name>[/<name>...], lowercase letters, digits, - and _" >&2; exit 2; }
    [[ $kv_key =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || { echo "secrets-store: the key is letters, digits, _, . and -" >&2; exit 2; }
    ;;
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
libexec=/usr/local/libexec/agent-box
work=/var/lib/agent-box
if [[ $env == dev ]]; then
  inventory=$keys/rebuild-dev/inventory/hosts.yml   # the dev inventory the rebuild wrapper reads
  settings=$work/secrets-store.json                 # private values the agent_box role writes from the inventory
  hold=$work/state/secrets-store.rebuilding         # from a rebuild until restore-rebuilt passes; the off-box send skips meanwhile
else
  inventory=$work/openbao-prod/inventory/hosts.yml  # the prod inventory openbao-prod builds, with the store name from its settings
  settings=$work/secrets-store-prod.json
  hold=$work/state/secrets-store-prod.rebuilding
fi
env_keys=$keys/$env
cacert=$env_keys/secrets-store-ca.crt
snapshots=$env_keys/openbao-snapshots   # the store's Raft snapshots, readable only with the seal key
snapshot_keep=24
# An earlier store's snapshots that clear-hold set aside: rotation never reads this folder, so they stay until
# the owner taps their removal (a delete under D-0042 rule 6).
kept=$env_keys/openbao-snapshots-kept
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

[[ -f $settings ]] || { echo "secrets-store: $settings is missing; set agent_box_secrets_store$([[ $env == dev ]] || echo _prod) in the inventory and run the agent_box role" >&2; exit 1; }
setting() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$settings" "$1"; }

# One store per run (D-0058 rule 10). The settings' address must be the one name this environment's inventory gives its
# c1 store (k8s_gitops_source_openbao_store_host), so no call reaches another store: dev's settings, keys and inventory
# never meet prod's.
# inventory_value KEY: the one value this environment's inventory gives KEY, anywhere in it; fails on none or two.
inventory_value() {
  "$libexec/ansible-venv/bin/python3" -I -c '
import sys, yaml
key, found = sys.argv[2], set()
def walk(n):
    if isinstance(n, dict):
        for k, v in n.items():
            if k == key and isinstance(v, str) and v: found.add(v)
            else: walk(v)
    elif isinstance(n, list):
        for i in n: walk(i)
walk(yaml.safe_load(open(sys.argv[1])))
if len(found) != 1: sys.exit(1)
print(found.pop())' "$inventory" "$1"
}
env_store() {
  local address host
  address=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("address") or "")' "$settings")
  [[ -n $address ]] || { echo "secrets-store: the settings have no store address yet (agent_box_secrets_store.address, set with the box's path to the store); refused" >&2; exit 1; }
  [[ -f $inventory ]] || { echo "secrets-store: the $env inventory $inventory is missing, so the $env store can't be checked; refused" >&2; exit 1; }
  host=$(inventory_value k8s_gitops_source_openbao_store_host) ||
    { echo "secrets-store: the $env inventory names no single $env store (k8s_gitops_source_openbao_store_host); refused" >&2; exit 1; }
  [[ $address == "$host" ]] || { echo "secrets-store: the settings' store address is not the $env c1 store the $env inventory names; refused" >&2; exit 1; }
}
env_store

# Every call goes to the store's admin address (D-0062) once the store has one, by the store's name, which its
# certificate carries: curl's --resolve <store name>:443:<admin address>, exported for the helpers below, which call curl
# the same way. Through Gateway apps OpenBao sees a Cilium address, so the admin login, bound to the box's /32, is
# refused there, and no listener for the store's name exists on the Gateway any more
# (docs/runbooks/set-up-the-secrets-store.md, "The box's path to the store"). On dev, with no admin address, every
# action refuses before any call: dev's names resolve to prod's Gateway, so dev has no other path. On prod, with no
# admin address yet, calls go by the store's name as they did before the admin path, unchanged until prod's admin
# address is set (that runbook, "On prod", step 9). The address is the one the cluster was given: the one
# k8s_gitops_source_openbao_admin_address in the inventory the cluster was built from. On dev that is the rebuild
# wrapper's copy of the dev inventory (its settings' admin_address, or dev's own pick from its pool); none until a
# rebuild has written it. On prod it is the inventory openbao-prod builds from its own settings.
admin_inv=$inventory
[[ $env == prod ]] || admin_inv=$work/rebuild-dev/inventory/hosts.yml
admin=''
if [[ $env == prod || -f $admin_inv ]]; then
  admin=$("$libexec/ansible-venv/bin/python3" -I -c '
import sys, yaml
found = set()
def walk(n):
    if isinstance(n, dict):
        for k, v in n.items():
            if k == "k8s_gitops_source_openbao_admin_address" and isinstance(v, str) and v: found.add(v)
            else: walk(v)
    elif isinstance(n, list):
        for i in n: walk(i)
walk(yaml.safe_load(open(sys.argv[1])))
if len(found) > 1: sys.exit(1)
print(found.pop() if found else "")' "$admin_inv") ||
    { echo "secrets-store: the $env inventory gives two admin addresses (k8s_gitops_source_openbao_admin_address); refused" >&2; exit 1; }
fi
[[ -z $admin || $admin =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
  { echo "secrets-store: the store's admin address is not one IPv4 address; refused" >&2; exit 1; }
[[ -n $admin || $env == prod ]] || {
  echo "secrets-store: the dev store has no admin address (k8s_gitops_source_openbao_admin_address in $admin_inv), the box's only path to it (D-0062); a dev rebuild with box_cidr in the settings writes one; refused" >&2
  exit 1
}
SECRETS_STORE_RESOLVE=''
[[ -z $admin ]] || SECRETS_STORE_RESOLVE="$(setting address):443:$admin"
export SECRETS_STORE_RESOLVE
# The box's /32 from the settings (empty until set), so a refused login can say whether OpenBao saw the box's own
# address without printing any address (secrets-store-kv.sh, login).
SECRETS_STORE_BOX_CIDR=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("box_cidr") or "")' "$settings")
export SECRETS_STORE_BOX_CIDR
curl() { if [[ -n ${SECRETS_STORE_RESOLVE:-} ]]; then command curl --resolve "$SECRETS_STORE_RESOLVE" "$@"; else command curl "$@"; fi; }

# Only the root-owned helpers beside this file run with the keys. One run at a time.
exec 9>"$work/state/secrets-store$([[ $env == dev ]] || echo -prod).lock"
flock -n 9 || { echo "secrets-store: another secrets-store run is going; try again when it ends" >&2; exit 1; }

# The admin AppRole's IDs (D-0038 rule 6), made here the first time and never printed. A file that exists
# is never replaced. The IDs carry no trailing newline, because the store reads each file whole. The seal
# key is not made here: the rebuild wrapper keeps it as a SOPS copy (D-0058 rule 3).
mkdir -p "$env_keys"
[[ -f $env_keys/openbao-admin-role-id ]] || openssl rand -hex 24 | tr -d '\n' > "$env_keys/openbao-admin-role-id"
[[ -f $env_keys/openbao-admin-secret-id ]] || openssl rand -hex 24 | tr -d '\n' > "$env_keys/openbao-admin-secret-id"

addr() { echo "https://$(setting address)"; }

# Every call that signs in checks the store against the CA file the box's path to the store writes.
[[ -s $cacert ]] || { echo "secrets-store: $cacert is missing; the box's path to the store (the Gateway PR) writes it; refused" >&2; exit 1; }

# SOPS's copy of every secret (D-0058 rules 8 and 9): only once the settings' sops_copies is true, the owner's tap.
sops_copies() {
  python3 -I -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("sops_copies") is True else 1)' "$settings" ||
    { echo "secrets-store: $action keeps SOPS copies, which wait for the owner's tap (sops_copies: true in agent_box_secrets_store); refused" >&2; exit 1; }
}
kv() { "$libexec/secrets-store-kv.sh" "$1" "$(addr)" "$cacert" "$env_keys" "$libexec" "${@:2}"; }

# snapshot-box when the settings say snapshot_box: true (the install tap), else admin. Anything but true is false.
snapshot_login() {
  python3 -I -c 'import json,sys; print("snapshot-box" if json.load(open(sys.argv[1])).get("snapshot_box") is True else "admin")' "$settings"
}

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
  # Shares on the box are for dev only (D-0038 rule 5, D-0058 rule 10: prod gets none); checked again here.
  [[ $env == dev ]] || { echo "secrets-store: prod gets no recovery shares (D-0038 rule 5, D-0058 rule 10); refused" >&2; exit 1; }
  ( env_store ) || { echo "secrets-store: recovery shares are made on the box for the dev store only; refused" >&2; exit 1; }
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

# Copy one Raft snapshot off the store, through AppRole snapshot-box once the install tap has turned it on, else the
# admin AppRole (agent pick 240). Fails loudly: never an empty file.
snapshot() {
  # During a rebuild the store is empty: a snapshot now would write its mark into the fresh store, which
  # restore-rebuilt's empty-store guard would then refuse, and it would be a snapshot of nothing.
  [[ ! -e $hold ]] || { echo "secrets-store: a rebuild is in progress ($hold); run restore-rebuilt first" >&2; exit 1; }
  # Through AppRole snapshot-box, not the admin, once the settings' snapshot_box is true (D-0038 rules 8 and 12,
  # agent pick 240). It is false until the owner's install tap.
  "$(dirname "$0")/secrets-store-snapshots.sh" take "$(addr)" "$cacert" "$env_keys" "$snapshots" "$snapshot_keep" "$env" "$(snapshot_login)"
}

# Put the newest snapshot of this store's own cluster back, never forced, and prove it by the mark, under the
# guards in secrets-store-restore.sh (mode same).
restore() {
  [[ ! -e $hold ]] || { echo "secrets-store: a rebuild is in progress ($hold); use restore-rebuilt" >&2; exit 1; }
  "$(dirname "$0")/secrets-store-restore.sh" same "$(addr)" "$cacert" "$env_keys" "$snapshots" "$hold" 120
}

# After a rebuild of the store: the newest snapshot of the store's previous cluster, under the guards in
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

# No write during a rebuild hold: the store is then the fresh one, and a key in it makes restore-rebuilt refuse (its
# empty-store step, secrets-store-restore.sh), so the earlier store's snapshots could no longer come back.
no_hold() {
  [[ ! -e $hold ]] || { echo "secrets-store: a rebuild is in progress ($hold); run restore-rebuilt, or clear-hold first; nothing written" >&2; exit 1; }
}

# One key into SOPS, then the store (rule 8). The value is this run's stdin, passed straight to the helper.
put() {
  sops_copies
  no_hold
  kv put "$kv_path" "$kv_key"
}

# Every value this environment's apps read through store c1 (namespace secret-source, docs/runbooks/seed-secret-source.md)
# into SOPS, then OpenBao, at c1/<name>, key `value`: the path and key the apps' ExternalSecrets read once the root's
# appSecretsStore is openbao (D-0058 rule 8; plan step 8a). The source is the file the rebuild seeds secret-source from:
# dev's is the box's own (rebuild.sh), prod's is the controller's copy (rebuild-prod.sh). Every name is checked before
# the first write. Each value goes from the file to the helper's stdin, byte for byte; only names are printed.
# put-apps (plan step 8a): every value c1's apps read at run time, each through put, so SOPS first, then OpenBao:
#   - the secret-source file, one <name>=<value> line each, to c1/<name> key value (store c1's values today);
#   - the identity values file the rebuild hands role k8s_identity, every KEY=value line to c1/identity key KEY (realm
#     lab's client secrets, passwords and TOTP seeds, and each app's client secret, which k8s_identity reads from there);
#   - prod only: the Cloudflare DNS-01 token file, trimmed as role k8s_certs trims it, to c1/cloudflare-api-token key value.
# Every file is read and every line checked before the first write. Only names are printed, never a value.
put_apps() {
  sops_copies
  no_hold
  local src ident token='' line name n=0 m=0 value
  if [[ $env == dev ]]; then
    src=$keys/rebuild-secret-source.env ident=$work/rebuild-dev/identity.env
  else
    src=$env_keys/secret-source.env ident=$env_keys/identity.env token=$env_keys/cloudflare-dns01-token.txt
  fi
  for f in "$src" "$ident" ${token:+"$token"}; do
    [[ -s $f ]] || { echo "secrets-store: $f is missing or empty; nothing written" >&2; exit 1; }
  done
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    name=${line%%=*}
    [[ $line == *=* && $name =~ ^[a-z0-9][a-z0-9_-]*$ ]] ||
      { echo "secrets-store: a line of $src is not <name>=<value> with a lowercase name; nothing written" >&2; exit 1; }
  done < "$src"
  # The same lines role k8s_identity reads (tasks/secrets.yml: ^[A-Z][A-Z0-9_]*=, the value after the first =).
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    [[ $line =~ ^[A-Z][A-Z0-9_]*= && -n ${line#*=} ]] ||
      { echo "secrets-store: a line of $ident is not KEY=<value> with an uppercase key and a value; nothing written" >&2; exit 1; }
  done < "$ident"
  if [[ -n $token ]]; then
    value=$(python3 -I -c 'import sys; print(open(sys.argv[1]).read().strip(), end="")' "$token")
    [[ -n $value && $value != *[[:space:]]* ]] || { echo "secrets-store: $token holds no single token; nothing written" >&2; exit 1; }
  fi
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    name=${line%%=*}
    printf '%s' "${line#*=}" | kv put "c1/$name" value
    n=$((n + 1))
  done < "$src"
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    printf '%s' "${line#*=}" | kv put c1/identity "${line%%=*}"
    m=$((m + 1))
  done < "$ident"
  if [[ -n $token ]]; then printf '%s' "$value" | kv put c1/cloudflare-api-token value; fi
  echo "secrets-store: put-apps: $n values from ${src##*/} at c1/<name> key value, $m from ${ident##*/} at c1/identity key <KEY>$([[ -z $token ]] || echo ", and the DNS-01 token at c1/cloudflare-api-token key value"), written to SOPS, then OpenBao"
}

compare() {
  sops_copies
  kv compare </dev/null
}

# A fresh store, filled from SOPS when no snapshot can bring it back (rule 8). Not during a rebuild hold: the earlier
# store's snapshots are then still waiting for restore-rebuilt, or for clear-hold to set them aside.
reseed() {
  sops_copies
  no_hold
  kv reseed </dev/null
  ( snapshot ) || { echo "secrets-store: reseeded, but the snapshot after it failed; run secrets-store snapshot" >&2; exit 1; }
}

case $action in
  status) status ;;
  recovery) recovery ;;
  snapshot) snapshot ;;
  restore) restore ;;
  restore-rebuilt) restore_rebuilt ;;
  clear-hold) clear_hold ;;
  put) put ;;
  put-apps) put_apps ;;
  # owner, test and check-test write keys, and a key in a fresh rebuilt store makes restore-rebuilt refuse, so they wait for the
  # hold like put; remove-test only deletes, so it may run (the reviewer's ask on #821).
  owner-login)
    [[ $named == remove-test || $named == plan ]] || no_hold
    # What the page's sign-in needs, from this environment's inventory where it already holds it (the helper's settings
    # override each): the zone (the first of k8s_gitops_source_zone, k8s_identity_zone and k8s_gateway_zone that is one plain
    # value, not a template) and the owner's user name (k8s_identity_owner_username). A key that is missing or is a template
    # is left empty, and the helper says which setting to give instead.
    plain_inventory_value() { local v; v=$(inventory_value "$1" 2>/dev/null) || return 1; [[ -n $v && $v != *"{{"* ]] || return 1; printf '%s' "$v"; }
    OWNER_LOGIN_ZONE='' OWNER_LOGIN_ZONE_KEY=''
    for k in k8s_gitops_source_zone k8s_identity_zone k8s_gateway_zone; do
      if OWNER_LOGIN_ZONE=$(plain_inventory_value "$k"); then OWNER_LOGIN_ZONE_KEY=$k; break; fi
      OWNER_LOGIN_ZONE=''
    done
    OWNER_LOGIN_USER=$(plain_inventory_value k8s_identity_owner_username) || OWNER_LOGIN_USER=''
    export OWNER_LOGIN_ZONE OWNER_LOGIN_ZONE_KEY OWNER_LOGIN_USER
    "$libexec/secrets-store-owner.sh" "$named" "$(addr)" "$cacert" "$env_keys" "$settings" "$libexec" ;;
  ssh-ca)
    [[ $named == plan || $named == check || $named == public ]] || no_hold
    plain_inventory_value() { local v; v=$(inventory_value "$1" 2>/dev/null) || return 1; [[ -n $v && $v != *"{{"* ]] || return 1; printf '%s' "$v"; }
    SSH_CA_ZONE='' SSH_CA_ZONE_KEY=''
    for k in k8s_gitops_source_zone k8s_identity_zone k8s_gateway_zone; do
      if SSH_CA_ZONE=$(plain_inventory_value "$k"); then SSH_CA_ZONE_KEY=$k; break; fi
      SSH_CA_ZONE=''
    done
    SSH_CA_ISSUER=''
    [[ -z $SSH_CA_ZONE ]] || SSH_CA_ISSUER="https://sso.$SSH_CA_ZONE/realms/lab"
    export SSH_CA_ZONE SSH_CA_ZONE_KEY SSH_CA_ISSUER
    "$libexec/secrets-store-ssh.sh" "$named" "$(addr)" "$cacert" "$env_keys" "$settings" "$libexec" "${ssh_args[@]}" ;;
  compare) compare ;;
  reseed) reseed ;;
esac
