#!/bin/bash
# /usr/local/libexec/openbao-drill.sh PORT SNAPSHOT_DIR WAIT: the weekly restore drill (D-0038 rule 8,
# Confirmation 4). It restores the newest snapshot into a throwaway server on this VM, proves that the snapshot's
# data came back, and deletes the copy. Run only by openbao-drill.service, which gives it:
#   PrivateNetwork=yes  only a loopback device, so the throwaway can't reach the live store or anything else,
#                       even when the restored Raft configuration names the live store's cluster address;
#   TemporaryFileSystem /var/lib/openbao-drill (the throwaway's storage) and /var/log/openbao (so the audit
#                       device that comes back with the restored data writes there, never to the store's log).
# Steps, each printed as one line with no value in it:
#   1 only loopback      the unit's network namespace holds lo and nothing else
#   2 snapshot           the newest raft-*.snap in SNAPSHOT_DIR
#   3 throwaway up       bao server from /etc/openbao/drill.hcl, as user openbao, answers "not initialized"
#   4 init               sys/init with no recovery shares: a root token for the empty throwaway only
#   5 restore            sys/storage/raft/snapshot-force with the snapshot (force: the throwaway's keys are new)
#   6 unsealed           health 200 again: the restored keyring opened with the store's own static seal key
#   7 old token refused  the throwaway's root token from step 4 is refused: its data was replaced
#   8 known login        the store's snapshot AppRole (IDs in /etc/openbao/snapshot) signs in
#   9 its policy         and lookup-self shows policy snapshot, as the store gave it
#  10 copy deleted       the throwaway is stopped and its storage is gone
# On any failure too, the throwaway is stopped and its storage deleted. No token or ID is printed or passed as an argument.
set -euo pipefail
umask 077
port=$1 snaps=$2 wait=$3
addr=https://127.0.0.1:$port/v1
cacert=/opt/openbao/tls/tls.crt
ids=/etc/openbao/snapshot
server=''
root_token='' token=''

step() { echo "openbao-drill: $1 ok"; }
die() { echo "openbao-drill: $1 FAIL: $2" >&2; exit 1; }

# A fixed path, never a variable, so no unset or wrong value can turn this into a wider delete.
cleanup() {
  if [[ -n $server ]]; then kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; fi
  rm -rf -- /var/lib/openbao-drill/raft
}
trap cleanup EXIT

# health: the HTTP code of sys/health (200 active, 501 not initialized, 503 sealed).
health() { curl -s -o /dev/null -w '%{http_code}' --cacert "$cacert" "$addr/sys/health" || true; }
wait_for() { # code, step name
  local i
  for ((i = 0; i < wait; i++)); do [[ $(health) == "$1" ]] && return 0; sleep 1; done
  die "$2" "health never answered $1 within ${wait}s"
}
# call METHOD PATH TOKEN [curl args...]: the token goes in on stdin as a header, never in the argument list.
call() {
  local method=$1 path=$2 tok=$3
  shift 3
  curl -s --cacert "$cacert" -X "$method" -H @- "$@" "$addr/$path" <<<"X-Vault-Token: $tok"
}
code() { # METHOD PATH TOKEN: the HTTP code only
  call "$1" "$2" "$3" -o /dev/null -w '%{http_code}' || true
}
# field KEY...: the value at those keys of the JSON on stdin; a list prints as its items joined by spaces.
field() {
  python3 -I -c '
import json, sys
v = json.load(sys.stdin)
for k in sys.argv[1:]:
    v = v[k]
print(" ".join(v) if isinstance(v, list) else v)' "$@"
}

[[ $(ip -o link show | awk -F': ' '{print $2}') == lo ]] || die "1 only loopback" "a device other than lo is present"
step "1 only loopback"

snap=$(find "$snaps" -maxdepth 1 -name 'raft-*.snap' -type f -printf '%T@ %p\n' | sort -rn | head -n 1 | cut -d' ' -f2-)
[[ -n $snap && -s $snap ]] || die "2 snapshot" "no snapshot in $snaps"
echo "openbao-drill: 2 snapshot ok: $(basename "$snap")"

install -d -o openbao -g openbao -m 0700 /var/lib/openbao-drill/raft
chown openbao:openbao /var/log/openbao
setpriv --reuid=openbao --regid=openbao --init-groups bao server -config=/etc/openbao/drill.hcl \
  >/var/lib/openbao-drill/server.log 2>&1 &
server=$!
wait_for 501 "3 throwaway up"
step "3 throwaway up"

root_token=$(curl -s --cacert "$cacert" -X PUT --data '{"recovery_shares": 0, "recovery_threshold": 0}' \
  "$addr/sys/init" | field root_token) || die "4 init" "no root token in the reply"
[[ -n $root_token ]] || die "4 init" "no root token in the reply"
wait_for 200 "4 init"
step "4 init"

rc=$(call POST sys/storage/raft/snapshot-force "$root_token" --data-binary "@$snap" -o /dev/null -w '%{http_code}') || true
[[ $rc == 200 || $rc == 204 ]] || die "5 restore" "HTTP $rc"
step "5 restore"

# The restore call returns before the data is in place (Vault's restore page), so wait for both: health 200
# with the restored keyring, and the throwaway's own token gone with its old data.
for ((i = 0; i < wait; i++)); do
  [[ $(health) == 200 && $(code GET auth/token/lookup-self "$root_token") == 403 ]] && break
  sleep 1
done
[[ $(health) == 200 ]] || die "6 unsealed" "health never answered 200 within ${wait}s of the restore"
step "6 unsealed"
rc=$(code GET auth/token/lookup-self "$root_token")
[[ $rc == 403 ]] || die "7 old token refused" "HTTP $rc: the throwaway's own token still works, so its data was not replaced"
root_token=
step "7 old token refused"

token=$(python3 -I -c 'import json, sys; print(json.dumps({"role_id": open(sys.argv[1]).read(), "secret_id": open(sys.argv[2]).read()}))' \
  "$ids/role-id" "$ids/secret-id" | curl -s --cacert "$cacert" -X POST --data @- "$addr/auth/approle/login" |
  field auth client_token) || die "8 known login" "the snapshot AppRole did not sign in"
[[ -n $token ]] || die "8 known login" "the snapshot AppRole did not sign in"
step "8 known login"

policies=$(call GET auth/token/lookup-self "$token" | field data policies) || die "9 its policy" "lookup-self failed"
call POST auth/token/revoke-self "$token" -o /dev/null || true
token=
[[ " $policies " == *" snapshot "* ]] || die "9 its policy" "policy snapshot not on the token"
step "9 its policy"

cleanup
server=''
[[ ! -e /var/lib/openbao-drill/raft ]] || die "10 copy deleted" "the throwaway's storage is still there"
step "10 copy deleted"
echo "PASS: restore drill: $(basename "$snap") restored into a throwaway server; the snapshot login and its policy read back; copy deleted"
