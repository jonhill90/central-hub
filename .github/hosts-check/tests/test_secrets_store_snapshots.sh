#!/usr/bin/env bash
# roles/agent_box/files/secrets-store-snapshots.sh (pick 239), on fake snapshot files:
#   1. rotate keeps the newest KEEP in the folder, with their .cluster files, and removes the older ones.
#   2. rotate never touches the kept folder, beside it or inside the snapshot folder.
#   3. keep moves every snapshot not of the current cluster, or with no .cluster file, with its .cluster file,
#      into the kept folder, and leaves the current cluster's in place; it prints how many it moved.
#   4. keep never overwrites a file already in the kept folder: it stops and fails.
#   5. Bad arguments are refused.
# take (pick 240), against a stand-in curl that plays the store and takes only snapshot-box's IDs:
#   6. It signs in as snapshot-box, writes kv/dev/snapshot-mark with the snapshot's own time, saves the snapshot
#      with its cluster ID, revokes the token and rotates.
#   7. The admin's IDs are never used: with only those, it fails and saves nothing.
#   8. A refused mark write or an empty snapshot fails, and no snapshot file is left.
#   9. The token never shows in curl's arguments or the output.
# Usage: .github/hosts-check/tests/test_secrets_store_snapshots.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
helper=$root/hosts/ansible/roles/agent_box/files/secrets-store-snapshots.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
s=$t/snaps k=$t/kept
mk() { # stamp cluster [dir]
  local d=${3:-$s}
  mkdir -p "$d"; echo "snap $1" > "$d/raft-$1.snap"
  [[ -z $2 ]] || echo "$2" > "$d/raft-$1.snap.cluster"
}
count() { find "$1" -maxdepth 1 -name 'raft-*.snap' -type f 2>/dev/null | wc -l; }

# 1 and 2
for h in 01 02 03 04 05; do mk "20261114T${h}0000Z" cluster-new; done
mk 20261113T000000Z cluster-old "$k"
mk 20261113T000000Z cluster-old "$s/inner"
bash "$helper" rotate "$s" 2
if [[ $(count "$s") == 2 && -e $s/raft-20261114T050000Z.snap && -e $s/raft-20261114T040000Z.snap.cluster && ! -e $s/raft-20261114T030000Z.snap.cluster ]]; then
  ok "1. rotate keeps the newest 2 with their .cluster files"
else bad "1. $(ls "$s")"; fi
[[ $(count "$k") == 1 && -e $k/raft-20261113T000000Z.snap.cluster && $(count "$s/inner") == 1 ]] \
  && ok "2. rotate never touches the kept folder, beside or inside" || bad "2. $(ls "$k" "$s/inner")"

# 3
rm -rf "$s" "$k"
mk 20261114T080000Z cluster-old; mk 20261114T090000Z cluster-old; mk 20261114T095000Z ""
mk 20261114T100000Z cluster-new
out=$(bash "$helper" keep "$s" "$k" cluster-new)
if [[ $out == 3 && $(count "$k") == 3 && -e $k/raft-20261114T090000Z.snap.cluster && $(count "$s") == 1 && -e $s/raft-20261114T100000Z.snap.cluster ]] &&
   [[ $(stat -c %a "$k") == 700 ]]; then
  ok "3. keep moves the other clusters' snapshots (and one with no cluster) aside, mode 700, and leaves the current one"
else bad "3. out=$out $(ls "$s" "$k")"; fi
bash "$helper" rotate "$s" 1
[[ $(count "$k") == 3 ]] && ok "3b. after keep, rotation leaves the kept snapshots alone" || bad "3b. $(ls "$k")"

# 4
mk 20261114T080000Z cluster-old
echo original > "$k/keep-check"; cp "$k/raft-20261114T080000Z.snap" "$t/before"
if bash "$helper" keep "$s" "$k" cluster-new > "$t/out" 2>&1; then bad "4. an existing file was not refused"
elif grep -q 'exists already' "$t/out" && cmp -s "$k/raft-20261114T080000Z.snap" "$t/before" && [[ -e $s/raft-20261114T080000Z.snap ]]; then
  ok "4. keep refuses to overwrite a file in the kept folder and moves nothing over it"
else bad "4. $(cat "$t/out")"; fi

# 5
r=0
bash "$helper" rotate "$s" 0 2>/dev/null && r=1
bash "$helper" keep "$s" "$k" "" 2>/dev/null && r=1
bash "$helper" delete "$s" 2>/dev/null && r=1
[[ $r == 0 ]] && ok "5. bad arguments are refused" || bad "5. a bad call was taken"

# take: a stand-in curl
mkdir -p "$t/bin" "$t/keys"
printf 'sb-role-fake' > "$t/keys/openbao-snapshot-box-role-id"; printf 'sb-secret-fake' > "$t/keys/openbao-snapshot-box-secret-id"
printf 'admin-role-fake' > "$t/keys/openbao-admin-role-id"; printf 'admin-secret-fake' > "$t/keys/openbao-admin-secret-id"
: > "$t/ca.crt"
cat > "$t/bin/curl" <<'SH'
#!/bin/bash
echo "$*" >> "$T/argv"
method=GET out="" data="" hdr=false url="" fail=false
while [[ $# -gt 0 ]]; do
  case $1 in
    -X) method=$2; shift ;;
    -o) out=$2; shift ;;
    --data) data=$2; shift ;;
    -H) [[ $2 == @- ]] && hdr=true; shift ;;
    --cacert) shift ;;
    --fail-with-body) fail=true ;;
    -sS|-s) ;;
    *) url=$1 ;;
  esac
  shift
done
tok="" body_in=""
if $hdr; then tok=$(sed -n 's/^X-Vault-Token: //p'); elif [[ $data == @- ]]; then body_in=$(cat); fi
path=${url#*/v1/}
echo "$method $path" >> "$T/calls"
code=200 body=""
case $path in
  sys/health) body='{"cluster_id": "cluster-new"}' ;;
  auth/approle/login)
    if [[ $body_in == '{"role_id": "sb-role-fake", "secret_id": "sb-secret-fake"}' ]]; then body='{"auth": {"client_token": "tok-sb-secret"}}'
    else code=400; body='{"errors": ["invalid role or secret ID"]}'; fi ;;
  kv/data/dev/snapshot-mark)
    if [[ $tok == tok-sb-secret && $method == POST && $TAKE != markfail ]]; then echo "$data" > "$T/mark"; else code=403; fi ;;
  sys/storage/raft/snapshot)
    if [[ $tok == tok-sb-secret && $method == GET ]]; then [[ $TAKE == empty ]] && body='' || body='RAFTDATA'; else code=403; fi ;;
  auth/token/revoke-self) echo revoked >> "$T/revoked"; code=204 ;;
  *) code=404 ;;
esac
if [[ -n $out ]]; then printf '%s' "$body" > "$out"; else printf '%s' "$body"; fi
$fail && [[ $code -ge 400 ]] && exit 22
exit 0
SH
chmod +x "$t/bin/curl"
take() { # stub mode
  rm -f "$t/calls" "$t/mark" "$t/revoked"
  TAKE=$1 T=$t PATH="$t/bin:$PATH" bash "$helper" take https://store.invalid "$t/ca.crt" "$t/keys" "$t/tk" 2 dev > "$t/out" 2>&1 && rc=0 || rc=$?
  tout+=$(cat "$t/out")
}
tout=""
rm -rf "$t/tk"; mkdir -p "$t/tk"
for h in 01 02; do echo old > "$t/tk/raft-20261101T${h}0000Z.snap"; echo cluster-new > "$t/tk/raft-20261101T${h}0000Z.snap.cluster"; done

# 6
take ok
new=$(find "$t/tk" -maxdepth 1 -name 'raft-2026111[4-9]*.snap' -o -maxdepth 1 -name 'raft-20[3-9]*.snap' | head -n 1)
new=$(find "$t/tk" -maxdepth 1 -name 'raft-*.snap' -newer "$t/ca.crt" -printf '%f\n' | sort | tail -n 1)
stamp=${new#raft-}; stamp=${stamp%.snap}
if [[ $rc -eq 0 && -n $new && $(cat "$t/tk/$new") == RAFTDATA && $(cat "$t/tk/$new.cluster") == cluster-new && $(cat "$t/mark") == *"\"taken\": \"$stamp\""* ]] &&
   [[ -s $t/revoked && $(count "$t/tk") == 2 && ! -e $t/tk/raft-20261101T010000Z.snap ]] && grep -q "^secrets-store: snapshot $new, 8 bytes" "$t/out"; then
  ok "6. take signs in as snapshot-box, writes the mark with the snapshot's time, saves it with its cluster, revokes, rotates"
else bad "6. rc=$rc $(cat "$t/out") mark=$(cat "$t/mark" 2>/dev/null) $(ls "$t/tk")"; fi

# 7
cp "$t/keys/openbao-snapshot-box-role-id" "$t/sb-role"; cp "$t/keys/openbao-snapshot-box-secret-id" "$t/sb-secret"
cp "$t/keys/openbao-admin-role-id" "$t/keys/openbao-snapshot-box-role-id"; cp "$t/keys/openbao-admin-secret-id" "$t/keys/openbao-snapshot-box-secret-id"
before=$(count "$t/tk"); take ok
[[ $rc -ne 0 ]] && grep -q 'snapshot-box did not sign in' "$t/out" && [[ $(count "$t/tk") == "$before" ]] && ! grep -q raft/snapshot "$t/calls" \
  && ok "7. with the admin's IDs, take fails and saves nothing" || bad "7. rc=$rc $(cat "$t/out")"
cp "$t/sb-role" "$t/keys/openbao-snapshot-box-role-id"; cp "$t/sb-secret" "$t/keys/openbao-snapshot-box-secret-id"

# 8
sleep 1; before=$(count "$t/tk"); take markfail; r8a=$rc o8a=$(cat "$t/out"); s8a=$(grep -c 'raft/snapshot' "$t/calls" || true)
take empty
if [[ $r8a -ne 0 && $o8a == *"snapshot failed or empty"* && $s8a == 0 && $rc -ne 0 && $(count "$t/tk") == "$before" ]] && ! ls "$t/tk"/*.part >/dev/null 2>&1 && [[ -s $t/revoked ]]; then
  ok "8. a refused mark write, or an empty snapshot, fails with no file left, and the token is still revoked"
else bad "8. rc=$r8a/$rc $o8a / $(cat "$t/out")"; fi

# 9
if grep -q 'tok-sb-secret\|sb-secret-fake' "$t/argv" || [[ $tout == *tok-sb* || $tout == *sb-secret-fake* ]]; then bad "9. the token or secret ID shows in arguments or output"
else ok "9. no token or secret ID in curl's arguments or the output"; fi
exit "$fail"
