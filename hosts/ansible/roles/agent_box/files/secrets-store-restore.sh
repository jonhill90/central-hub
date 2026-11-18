#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store-restore.sh MODE ADDR CACERT KEYS SNAPSHOTS HOLD WAIT [NAMED]: run only by the
# `secrets-store` wrapper, under its lock. No token or ID is printed or passed as an argument; the step lines name
# the step and the snapshot's file name only.
#
# MODE same (`secrets-store restore`, D-0038 Confirmations 4 and 7, pick 239): the newest snapshot of the store's
# own cluster goes back onto the same store, never forced.
#   1 snapshot          the newest raft-*.snap whose .cluster file names the store's current cluster
#   1b shares           see below
#   2 mark moved        kv/<env>/snapshot-mark is set to before-restore-<now>, so only the restore can put the
#                       snapshot's own time back
#   3 restore           plain only; any refusal stops the run
#   4 mark reads back   within WAIT seconds, sys/health 200 and a fresh login reads the snapshot's own time
#   then, measured and printed, not a gate: whether the token from before the restore is refused now
#
# MODE rebuilt (`secrets-store restore-rebuilt`, Confirmation 5, pick 238): after the dev store's VM was destroyed
# and rebuilt from code, the newest snapshot of the store's previous cluster.
#   1 snapshot          the newest raft-*.snap whose .cluster file names a cluster other than the current one; a
#                       snapshot of the rebuilt store, or one with no .cluster file, is never picked. With NAMED
#                       (an exact file name, e.g. one moved back from the kept folder), that file only: refused
#                       if it is missing, has no .cluster file, or is of the current cluster
#   1b shares           see below
#   2 empty store       kv/ holds nothing but c1/check, the fixed word configure writes; a listing that answers
#                       anything but 200 or 404 refuses
#   3 restore           plain first; forced only when OpenBao refuses it with the unseal-keys text below, any other
#                       refusal stops the run
#   4 unsealed          sys/health 200 again
#   5 old token refused the token from before the restore is refused: the data was replaced
#   6 mark reads back   kv/<env>/snapshot-mark holds the picked snapshot's own time
#   then the hold is removed, so the hourly off-box send runs again.
#
# 1b shares (both modes, pick 239): once the recovery shares exist, a snapshot taken before them is refused. A
# restore brings back the recovery keys of the snapshot's time, so it would leave the box's shares useless
# (discuss.hashicorp.com, "Performing restore from snapshot invalidates existing auto-unseal recovery keys"). The
# shares' time is openbao-recovery.made, which `recovery` writes before it asks for them; the snapshot's time must
# be strictly later. With no .made file, the shares file's own time is used, with a warning.
set -euo pipefail
# On dev, secrets-store.sh sets SECRETS_STORE_RESOLVE (<store name>:443:<dev Gateway address>), because dev's names
# resolve to prod's Gateway; every curl here goes there. Unset (prod): curl as it is.
curl() { if [[ -n ${SECRETS_STORE_RESOLVE:-} ]]; then command curl --resolve "$SECRETS_STORE_RESOLVE" "$@"; else command curl "$@"; fi; }
umask 077
mode=$1 addr=$2/v1 cacert=$3 keys=$4 snaps=$5 hold=$6 wait=$7 named=${8:-}
# The environment is the keys folder's own name, dev or prod (the wrapper passes <keys>/<env>): it names the mark.
env=$(basename -- "$keys")
[[ $env == dev || $env == prod ]] || { echo "secrets-store-restore: the keys folder must be .../dev or .../prod" >&2; exit 2; }
case $mode in
  same) name=restore ;;
  rebuilt) name=restore-rebuilt ;;
  *) echo "secrets-store-restore: mode must be same or rebuilt" >&2; exit 2 ;;
esac
# The refusal text a Vault user reported for a snapshot from another cluster (discuss.hashicorp.com, "Raft: how to
# restore from 3-node HA cluster to 1-node DR instance"). If OpenBao words it otherwise, the run stops as "other
# refusal" and this line is changed to match, once measured.
keys_text='possibly the snapshot is using a different set of unseal keys'
token='' new_token=''

step() { echo "secrets-store $name: $1 ok${2:+: $2}"; }
die() { echo "secrets-store $name: $1 FAIL: $2" >&2; exit 1; }
revoke() {
  local t
  for t in "$token" "$new_token"; do
    [[ -n $t ]] && call POST auth/token/revoke-self "$t" -o /dev/null >/dev/null 2>&1 || true
  done
}
trap revoke EXIT

health() { curl -s -o /dev/null -w '%{http_code}' --cacert "$cacert" "$addr/sys/health" || true; }
# call METHOD PATH TOKEN [curl args...]: the token goes in on stdin as a header, never in the argument list.
call() {
  local method=$1 path=$2 tok=$3
  shift 3
  curl -s --cacert "$cacert" -X "$method" -H @- "$@" "$addr/$path" <<<"X-Vault-Token: $tok"
}
# code METHOD PATH TOKEN [curl args...]: the HTTP code only.
code() {
  local method=$1 path=$2 tok=$3
  shift 3
  call "$method" "$path" "$tok" "$@" -o /dev/null -w '%{http_code}' || true
}
# field KEY...: the value at those keys of the JSON on stdin; a list prints one item per line.
field() {
  python3 -I -c '
import json, sys
v = json.load(sys.stdin)
for k in sys.argv[1:]:
    v = v[k]
print("\n".join(v) if isinstance(v, list) else v)' "$@"
}
login() {
  python3 -I -c 'import json, sys; print(json.dumps({"role_id": open(sys.argv[1]).read().strip(), "secret_id": open(sys.argv[2]).read().strip()}))' \
    "$keys/openbao-admin-role-id" "$keys/openbao-admin-secret-id" |
    curl -s --cacert "$cacert" -X POST --data @- "$addr/auth/approle/login" | field auth client_token
}
mark() { call GET kv/data/$env/snapshot-mark "$1" | field data data taken; }

[[ $(health) == 200 ]] || die "0 store up" "sys/health is not 200; run apply and configure first"
current=$(curl -s --cacert "$cacert" "$addr/sys/health" | field cluster_id) || die "0 store up" "no cluster ID in sys/health"

# 1. The snapshot: of the current cluster (same) or of another one (rebuilt), or the one named.
snap=''
if [[ -n $named ]]; then
  [[ $mode == rebuilt ]] || die "1 snapshot" "only restore-rebuilt takes a snapshot name"
  [[ $named =~ ^raft-[0-9]{8}T[0-9]{6}Z\.snap$ ]] || die "1 snapshot" "$named is not a snapshot name"
  [[ -s $snaps/$named ]] || die "1 snapshot" "$named is not in $snaps; nothing restored"
  c=$(cat "$snaps/$named.cluster" 2>/dev/null || true)
  [[ -n $c ]] || die "1 snapshot" "$named has no .cluster file; nothing restored"
  [[ $c != "$current" ]] || die "1 snapshot" "$named is of the current store's cluster; nothing restored"
  snap=$named
fi
[[ -n $snap ]] || while read -r f; do
  c=$(cat "$snaps/$f.cluster" 2>/dev/null || true)
  [[ -n $c ]] || continue
  if [[ $mode == same && $c == "$current" ]] || [[ $mode == rebuilt && $c != "$current" ]]; then snap=$f; break; fi
done < <(find "$snaps" -maxdepth 1 -name 'raft-*.snap' -type f -printf '%f\n' 2>/dev/null | sort -r)
if [[ -z $snap || ! -s $snaps/$snap ]]; then
  [[ $mode == same ]] && die "1 snapshot" "no snapshot of this store's cluster in $snaps; run secrets-store snapshot first"
  die "1 snapshot" "no snapshot of an earlier cluster in $snaps; nothing to restore onto a rebuilt store"
fi
stamp=${snap#raft-}
stamp=${stamp%.snap}
step "1 snapshot" "$snap${named:+ (named)}"

# 1b. Never a snapshot older than the recovery shares.
if [[ -e $keys/openbao-recovery.json ]]; then
  made=$(cat "$keys/openbao-recovery.made" 2>/dev/null || true)
  if [[ -z $made ]]; then
    made=$(date -u -d "@$(stat -c %Y "$keys/openbao-recovery.json")" +%Y%m%dT%H%M%SZ)
    echo "secrets-store $name: WARNING: openbao-recovery.made is missing; the shares' time is taken from the shares file ($made), not recorded" >&2
  fi
  [[ $made =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || die "1b shares" "openbao-recovery.made does not hold a time; nothing restored"
  [[ $stamp > $made ]] || die "1b shares" "$snap was taken before the recovery shares were made ($made); restoring it would make them useless; nothing restored"
  step "1b shares" "snapshot is later than the shares"
else
  step "1b shares" "no recovery shares yet"
fi

token=$(login) && [[ -n $token ]] || die "2 sign-in" "the admin AppRole did not sign in"

if [[ $mode == same ]]; then
  # 2. Move the mark off, so that only the restore can bring the snapshot's own time back.
  rc=$(code POST kv/data/$env/snapshot-mark "$token" --data "{\"data\": {\"taken\": \"before-restore-$(date -u +%Y%m%dT%H%M%SZ)\"}}")
  [[ $rc == 200 || $rc == 204 ]] || die "2 mark moved" "writing kv/$env/snapshot-mark answered HTTP $rc; nothing restored"
  step "2 mark moved"

  # 3. Plain only.
  out=$(call POST sys/storage/raft/snapshot "$token" --data-binary "@$snaps/$snap" -w '\n%{http_code}') || true
  rc=${out##*$'\n'}
  [[ $rc == 200 || $rc == 204 ]] || die "3 restore" "OpenBao refused the plain restore, HTTP $rc; never forced on the same store"
  step "3 restore" plain

  # 4. The restore call returns before the data is in place: wait until a fresh login reads the snapshot's time.
  taken=''
  for ((i = 0; i < wait; i++)); do
    if [[ $(health) == 200 ]]; then
      new_token=$(login 2>/dev/null) || new_token=''
      if [[ -n $new_token ]]; then
        taken=$(mark "$new_token" 2>/dev/null) || taken=''
        [[ $taken == "$stamp" ]] && break
        call POST auth/token/revoke-self "$new_token" -o /dev/null >/dev/null 2>&1 || true
        new_token=''
      fi
    fi
    sleep 1
  done
  [[ $taken == "$stamp" ]] || die "4 mark reads back" "within ${wait}s the mark was ${taken:-not readable}, not $stamp"
  step "4 mark reads back"

  # Measured, not a gate: a same-cluster restore should drop the token made after the snapshot (pick 239).
  if [[ $(code GET auth/token/lookup-self "$token") == 403 ]]; then old=refused; else old='still works'; fi
  echo "secrets-store $name: measured: old token: $old"
  echo "PASS: restore: $snap restored (plain) onto the same store; its mark reads back"
  exit 0
fi

# 2. The store holds no data but configure's own word.
found=() queue=("")
while (( ${#queue[@]} )); do
  p=${queue[0]}
  queue=("${queue[@]:1}")
  # Only 200 (keys) and 404 (nothing there) count as an answer; any other code is a refusal, never "empty".
  out=$(call LIST "kv/metadata/$p" "$token" -w '\n%{http_code}') || true
  rc=${out##*$'\n'}
  [[ $rc == 404 ]] && continue
  [[ $rc == 200 ]] || die "2 empty store" "listing kv/$p answered HTTP ${rc:-nothing}; nothing restored"
  listed=$(field data keys <<<"${out%$'\n'*}") || die "2 empty store" "listing kv/$p gave no key list; nothing restored"
  while read -r k; do
    [[ -n $k ]] || continue
    if [[ $k == */ ]]; then queue+=("$p$k"); else found+=("$p$k"); fi
  done <<<"$listed"
done
for k in "${found[@]}"; do
  [[ $k == c1/check ]] || die "2 empty store" "the store holds kv/$k, so it is not a fresh rebuild; nothing restored"
done
step "2 empty store"

# 3. Plain first; forced only on the unseal-keys refusal.
out=$(call POST sys/storage/raft/snapshot "$token" --data-binary "@$snaps/$snap" -w '\n%{http_code}') || true
rc=${out##*$'\n'}
if [[ $rc == 200 || $rc == 204 ]]; then
  how=plain
elif [[ $out == *"$keys_text"* ]]; then
  rc=$(call POST sys/storage/raft/snapshot-force "$token" --data-binary "@$snaps/$snap" -o /dev/null -w '%{http_code}') || true
  [[ $rc == 200 || $rc == 204 ]] || die "3 restore" "the forced restore answered HTTP $rc"
  how=forced
else
  die "3 restore" "other refusal, HTTP $rc; not forced"
fi
step "3 restore" "$how"

# 4 and 5. The restore call returns before the data is in place: wait for both.
for ((i = 0; i < wait; i++)); do
  [[ $(health) == 200 && $(code GET auth/token/lookup-self "$token") == 403 ]] && break
  sleep 1
done
[[ $(health) == 200 ]] || die "4 unsealed" "health never answered 200 within ${wait}s of the restore"
step "4 unsealed"
rc=$(code GET auth/token/lookup-self "$token")
[[ $rc == 403 ]] || die "5 old token refused" "HTTP $rc: the token from before the restore still works, so the data was not replaced"
token=''
step "5 old token refused"

# 6. The mark inside the snapshot reads back.
new_token=$(login) && [[ -n $new_token ]] || die "6 mark reads back" "the admin AppRole did not sign in after the restore"
taken=$(mark "$new_token") || die "6 mark reads back" "no kv/$env/snapshot-mark"
[[ $taken == "$stamp" ]] || die "6 mark reads back" "the mark is $taken, not $stamp"
step "6 mark reads back"

rm -f -- "$hold"
echo "PASS: restore-rebuilt: $snap restored ($how) onto the rebuilt store; its mark reads back; hold removed"
