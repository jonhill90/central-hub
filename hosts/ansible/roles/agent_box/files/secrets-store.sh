#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store.sh: the agent box's calls to the lab's secrets store, OpenBao,
# on dev (docs/runbooks/set-up-the-secrets-store.md, D-0038 as D-0058 changes it). It runs as user `keys`
# through sudo, so the session that asks for it never sees the AppRole IDs or the recovery shares. Installed
# by the agent_box role; root owns it.
#   sudo -n -u keys /usr/local/libexec/agent-box/secrets-store.sh recovery|status|snapshot|restore|restore-rebuilt [raft-<time>.snap]|clear-hold
# The store VM's actions (plan, apply, destroy and configure) are gone: no store VM was ever built, and the
# store runs inside c1 (D-0058). Until the box's in-cluster work (rework PR 3b) points these calls at c1's
# store, they still read the store's address and CA file from the settings below, and nothing writes the CA
# file or the rebuild hold. recovery: makes the recovery shares once (self-
# initialization makes none) into the keys folder, records their time and takes a snapshot that holds them.
# status: sys/health, which holds no secret. snapshot: writes kv/dev/snapshot-mark (one key, its own time, no
# secret), then copies a Raft snapshot off the store into the keys folder, with the store's cluster ID beside it.
# restore: puts the newest snapshot of the same cluster back, never forced, and proves it by the mark (D-0038
# Confirmations 4 and 7, pick 239). restore-rebuilt: after a rebuild of the store, puts back the newest snapshot
# of the store's previous cluster, forced only if OpenBao refuses it for the keys (Confirmation 5, pick 238).
# Both refuse a snapshot older than the recovery shares. A rebuild leaves a hold that stops the hourly off-box send
# until restore-rebuilt passes; clear-hold sets the earlier store's snapshots aside in a kept folder that rotation
# never reads, then removes it, when the rebuilt store is to stay as it is. Dev only: every
# action refuses a store outside 550-599.
set -euo pipefail
umask 077

usage() { echo "usage: secrets-store recovery|status|snapshot|restore|restore-rebuilt [raft-<time>.snap]|clear-hold" >&2; exit 2; }
named=''
case ${1:-} in
  recovery | status | snapshot | restore | clear-hold) action=$1; [[ $# -eq 1 ]] || usage ;;
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
settings=$work/secrets-store.json   # private values the agent_box role writes from the inventory
cacert=$env_keys/secrets-store-ca.crt
snapshots=$env_keys/openbao-snapshots   # the store's Raft snapshots, readable only with the seal key
snapshot_keep=24
# An earlier store's snapshots that clear-hold set aside: rotation never reads this folder, so they stay until
# the owner taps their removal (a delete under D-0042 rule 6).
kept=$env_keys/openbao-snapshots-kept
hold=$work/state/secrets-store.rebuilding   # from a rebuild until restore-rebuilt passes; the off-box send skips meanwhile
export HOME=$work PATH=/usr/local/bin:/usr/bin:/bin

[[ -f $settings ]] || { echo "secrets-store: $settings is missing; set agent_box_secrets_store in the inventory and run the agent_box role" >&2; exit 1; }
setting() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$settings" "$1"; }

# Dev only. The store's IDs are 500-599 (agent pick 226, under STD-0001's next-free-hundred rule); dev
# is 550-599, as dev is 250-257 among 200-299. A prod store gets its own wrapper and keys folder after
# dev passes (D-0035 rule 3), and its recovery shares go only to the owner's Mac (D-0038 rule 5). The
# in-cluster rework (PR 3b) replaces this check with the dev c1 store's address (D-0058 rule 10).
vm_id=$(setting vm_id)
[[ $vm_id =~ ^5[5-9][0-9]$ ]] || { echo "secrets-store: VM ID $vm_id is not a dev store ID (550-599); refused" >&2; exit 1; }

# Only the root-owned helpers beside this file run with the keys. One run at a time.
exec 9>"$work/state/secrets-store.lock"
flock -n 9 || { echo "secrets-store: another secrets-store run is going; try again when it ends" >&2; exit 1; }

# The admin AppRole's IDs (D-0038 rule 6), made here the first time and never printed. A file that exists
# is never replaced. The IDs carry no trailing newline, because the store reads each file whole. The seal
# key is not made here: the rebuild wrapper keeps it as a SOPS copy (D-0058 rule 3).
mkdir -p "$env_keys"
[[ -f $env_keys/openbao-admin-role-id ]] || openssl rand -hex 24 | tr -d '\n' > "$env_keys/openbao-admin-role-id"
[[ -f $env_keys/openbao-admin-secret-id ]] || openssl rand -hex 24 | tr -d '\n' > "$env_keys/openbao-admin-secret-id"

addr() { echo "https://$(setting address)"; }

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

# Copy one Raft snapshot off the store, through AppRole snapshot-box once the install tap has turned it on, else the
# admin AppRole (agent pick 240). Fails loudly: never an empty file.
snapshot() {
  # During a rebuild the store is empty: a snapshot now would write its mark into the fresh store, which
  # restore-rebuilt's empty-store guard would then refuse, and it would be a snapshot of nothing.
  [[ ! -e $hold ]] || { echo "secrets-store: a rebuild is in progress ($hold); run restore-rebuilt first" >&2; exit 1; }
  # Through AppRole snapshot-box, not the admin, once the settings' snapshot_box is true (D-0038 rules 8 and 12,
  # agent pick 240). It is false until the owner's install tap.
  "$(dirname "$0")/secrets-store-snapshots.sh" take "$(addr)" "$cacert" "$env_keys" "$snapshots" "$snapshot_keep" dev "$(snapshot_login)"
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

case $action in
  status) status ;;
  recovery) recovery ;;
  snapshot) snapshot ;;
  restore) restore ;;
  restore-rebuilt) restore_rebuilt ;;
  clear-hold) clear_hold ;;
esac
