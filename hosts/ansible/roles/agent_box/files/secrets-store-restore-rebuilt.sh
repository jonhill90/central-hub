#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store-restore-rebuilt.sh ADDR CACERT KEYS SNAPSHOTS HOLD WAIT: run only by
# `secrets-store restore-rebuilt`, under its lock (D-0038 Confirmation 5, pick 238). After the dev store's VM was
# destroyed and rebuilt from code, it puts back the newest snapshot of the store's previous cluster.
# Guards, each refusing with no change:
#   1 snapshot          the newest raft-*.snap whose .cluster file names a cluster other than the store's current
#                       one; a snapshot of the rebuilt store, or one with no .cluster file, is never picked
#   2 empty store       kv/ holds nothing but c1/check, the fixed word configure writes
#   3 restore           plain first; forced only when OpenBao refuses it with the unseal-keys text below, any other
#                       refusal stops the run
#   4 unsealed          sys/health 200 again
#   5 old token refused the token from before the restore is refused: the data was replaced
#   6 mark reads back   kv/dev/snapshot-mark holds the picked snapshot's own time
# Then the hold is removed, so the hourly off-box send runs again. No token or ID is printed or passed as an
# argument; the step lines name the step and the snapshot's file name only.
set -euo pipefail
umask 077
addr=$1/v1 cacert=$2 keys=$3 snaps=$4 hold=$5 wait=$6
# The refusal text a Vault user reported for a snapshot from another cluster (discuss.hashicorp.com, "Raft: how to
# restore from 3-node HA cluster to 1-node DR instance"). If OpenBao words it otherwise, the run stops as "other
# refusal" and this line is changed to match, once measured.
keys_text='possibly the snapshot is using a different set of unseal keys'
token='' new_token=''

step() { echo "secrets-store restore-rebuilt: $1 ok${2:+: $2}"; }
die() { echo "secrets-store restore-rebuilt: $1 FAIL: $2" >&2; exit 1; }
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
code() { call "$1" "$2" "$3" -o /dev/null -w '%{http_code}' || true; }
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

[[ $(health) == 200 ]] || die "0 store up" "sys/health is not 200; run apply and configure first"
current=$(curl -s --cacert "$cacert" "$addr/sys/health" | field cluster_id) || die "0 store up" "no cluster ID in sys/health"

# 1. The newest snapshot of another cluster than the store's current one.
snap=''
while read -r f; do
  c=$(cat "$snaps/$f.cluster" 2>/dev/null || true)
  if [[ -n $c && $c != "$current" ]]; then snap=$f; break; fi
done < <(find "$snaps" -maxdepth 1 -name 'raft-*.snap' -type f -printf '%f\n' 2>/dev/null | sort -r)
[[ -n $snap && -s $snaps/$snap ]] || die "1 snapshot" "no snapshot of an earlier cluster in $snaps; nothing to restore onto a rebuilt store"
stamp=${snap#raft-}
stamp=${stamp%.snap}
step "1 snapshot" "$snap"

# 2. The store holds no data but configure's own word.
token=$(login) && [[ -n $token ]] || die "2 empty store" "the admin AppRole did not sign in"
found=() queue=("")
while (( ${#queue[@]} )); do
  p=${queue[0]}
  queue=("${queue[@]:1}")
  while read -r k; do
    [[ -n $k ]] || continue
    if [[ $k == */ ]]; then queue+=("$p$k"); else found+=("$p$k"); fi
  done < <(call LIST "kv/metadata/$p" "$token" | field data keys 2>/dev/null || true)
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
taken=$(call GET kv/data/dev/snapshot-mark "$new_token" | field data data taken) || die "6 mark reads back" "no kv/dev/snapshot-mark"
[[ $taken == "$stamp" ]] || die "6 mark reads back" "the mark is $taken, not $stamp"
step "6 mark reads back"

rm -f -- "$hold"
echo "PASS: restore-rebuilt: $snap restored ($how) onto the rebuilt store; its mark reads back; hold removed"
