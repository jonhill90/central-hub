#!/usr/bin/env bash
# roles/agent_box/files/secrets-store-restore-rebuilt.sh (pick 238, D-0038 Confirmation 5) against a stand-in for
# curl that plays a rebuilt dev store (fake values only):
#   1. OpenBao refuses the plain restore with the unseal-keys text: the forced one runs, the newest snapshot of the
#      previous cluster is picked (not a newer one of the rebuilt store), the mark reads back, the hold is removed.
#   2. OpenBao takes the plain restore: no forced call.
#   3. Any other refusal stops the run: no forced call, the hold stays.
#   4. Only snapshots of the current cluster, or with no .cluster file: refused before any restore.
#   5. The store holds a key besides c1/check: refused before any restore.
#   6. The token from before the restore still works: step 5 fails.
#   7. The mark does not match the snapshot's time: step 6 fails.
#   8. No token or AppRole ID shows in the output.
# Usage: .github/hosts-check/tests/test_secrets_store_restore_rebuilt.sh   (needs python3)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
mkdir -p "$t/bin" "$t/keys" "$t/snaps"
printf 'role-id-fake-value' > "$t/keys/openbao-admin-role-id"
printf 'secret-id-fake-value' > "$t/keys/openbao-admin-secret-id"
: > "$t/ca.crt"

cat > "$t/bin/curl" <<'SH'
#!/bin/bash
# The rebuilt store: phase rebuilt -> restored, in $T/phase; what it does on a restore is $MODE.
method=GET out="" fmt="" data="" hdr=false url=""
while [[ $# -gt 0 ]]; do
  case $1 in
    -X) method=$2; shift ;;
    -o) out=$2; shift ;;
    -w) fmt=$2; shift ;;
    --data|--data-binary) data=$2; shift ;;
    -H) [[ $2 == @- ]] && hdr=true; shift ;;
    --cacert) shift ;;
    -s) ;;
    *) url=$1 ;;
  esac
  shift
done
tok="" body_in=""
if $hdr; then tok=$(sed -n 's/^X-Vault-Token: //p'); elif [[ $data == @- ]]; then body_in=$(cat); fi
phase=$(cat "$T/phase" 2>/dev/null || echo rebuilt)
path=${url#*/v1/}
echo "$method $path" >> "$T/calls"
code=200 body=""
case $path in
  sys/health) body='{"cluster_id": "cluster-new", "sealed": false}' ;;
  auth/approle/login)
    if [[ $body_in == '{"role_id": "role-id-fake-value", "secret_id": "secret-id-fake-value"}' ]]; then
      if [[ $phase == restored ]]; then body='{"auth": {"client_token": "tok-after-secret"}}'
      else body='{"auth": {"client_token": "tok-before-secret"}}'; fi
    else code=400; fi ;;
  kv/metadata/*)
    p=${path#kv/metadata/}
    keys=$(grep -E "^${p}[^/]+/?$" "$T/kv" 2>/dev/null | sed "s|^$p||" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')
    if [[ $keys == '[]' ]]; then code=404; body='{"errors": []}'; else body="{\"data\": {\"keys\": $keys}}"; fi ;;
  sys/storage/raft/snapshot)
    case $MODE in
      plain) echo restored > "$T/phase"; echo "${data#@}" > "$T/restored"; code=204 ;;
      other) code=400; body='{"errors": ["something else went wrong"]}' ;;
      *) code=500; body='{"errors": ["could not verify hash file, possibly the snapshot is using a different set of unseal keys; use the snapshot-force API to bypass this check"]}' ;;
    esac ;;
  sys/storage/raft/snapshot-force)
    if [[ $tok == tok-before-secret ]]; then echo restored > "$T/phase"; echo "${data#@}" > "$T/restored"; code=204; else code=403; fi ;;
  auth/token/lookup-self)
    if [[ $tok == tok-before-secret && $phase == restored && $MODE != stale ]]; then code=403; fi ;;
  kv/data/dev/snapshot-mark)
    s=$(basename "$(cat "$T/restored")"); s=${s#raft-}; s=${s%.snap}
    [[ $MODE == nomark ]] && s=20990101T000000Z
    body="{\"data\": {\"data\": {\"taken\": \"$s\"}}}" ;;
  auth/token/revoke-self) code=204 ;;
  *) code=404 ;;
esac
[[ -n $out ]] || printf '%s' "$body"
[[ -n $fmt ]] && printf "${fmt//%\{http_code\}/%s}" "$code"
exit 0
SH
chmod +x "$t/bin/curl"
helper=$root/hosts/ansible/roles/agent_box/files/secrets-store-restore-rebuilt.sh

snapset() { # the standard set: two of the old cluster, two newer of the rebuilt store
  rm -f "$t/snaps/"*
  for s in 20261114T080000Z:cluster-old 20261114T090000Z:cluster-old 20261114T100000Z:cluster-new 20261114T110000Z:cluster-new; do
    echo "snap ${s%%:*}" > "$t/snaps/raft-${s%%:*}.snap"; echo "${s##*:}" > "$t/snaps/raft-${s%%:*}.snap.cluster"
  done
}
run() { # mode
  rm -f "$t/phase" "$t/restored" "$t/calls"
  date -u +%FT%TZ > "$t/hold"
  MODE=$1 T=$t PATH="$t/bin:$PATH" bash "$helper" https://store.invalid "$t/ca.crt" "$t/keys" "$t/snaps" "$t/hold" 3 > "$t/out" 2>&1 && rc=0 || rc=$?
  all+=$(cat "$t/out")
}
forced() { grep -q 'snapshot-force' "$t/calls"; }
restored() { grep -q 'sys/storage/raft/snapshot' "$t/calls"; }
all=""
printf 'c1/\nc1/check\n' > "$t/kv"

# 1
snapset; run keys
if [[ $rc -eq 0 ]] && grep -q '3 restore ok: forced' "$t/out" && grep -q '^PASS: restore-rebuilt: raft-20261114T090000Z.snap restored (forced)' "$t/out" &&
   [[ $(cat "$t/restored") == "$t/snaps/raft-20261114T090000Z.snap" && ! -e $t/hold ]]; then
  ok "1. unseal-keys refusal: forced; the previous cluster's newest snapshot; mark reads back; hold removed"
else bad "1. rc=$rc $(cat "$t/out")"; fi

# 2
snapset; run plain
[[ $rc -eq 0 ]] && grep -q '3 restore ok: plain' "$t/out" && ! forced && ok "2. a plain restore taken: no forced call" || bad "2. rc=$rc $(cat "$t/out")"

# 3
snapset; run other
[[ $rc -ne 0 ]] && grep -q '3 restore FAIL: other refusal' "$t/out" && ! forced && [[ -e $t/hold ]] \
  && ok "3. another refusal stops the run: not forced, hold kept" || bad "3. rc=$rc $(cat "$t/out")"

# 4
rm -f "$t/snaps/"*
echo a > "$t/snaps/raft-20261114T100000Z.snap"; echo cluster-new > "$t/snaps/raft-20261114T100000Z.snap.cluster"
echo b > "$t/snaps/raft-20261114T080000Z.snap"
run keys
[[ $rc -ne 0 ]] && grep -q '1 snapshot FAIL' "$t/out" && ! restored && ok "4. only the rebuilt store's snapshots, or none with a cluster: refused before any restore" || bad "4. rc=$rc $(cat "$t/out")"

# 5
snapset; printf 'c1/\nc1/check\ndev/\ndev/other\n' > "$t/kv"; run keys
[[ $rc -ne 0 ]] && grep -q '2 empty store FAIL: the store holds kv/dev/other' "$t/out" && ! restored \
  && ok "5. a store holding a key besides c1/check: refused before any restore" || bad "5. rc=$rc $(cat "$t/out")"
printf 'c1/\nc1/check\n' > "$t/kv"

# 6
snapset; run stale
[[ $rc -ne 0 ]] && grep -q '5 old token refused FAIL' "$t/out" && ok "6. the old token still working fails step 5" || bad "6. rc=$rc $(cat "$t/out")"

# 7
snapset; run nomark
[[ $rc -ne 0 ]] && grep -q '6 mark reads back FAIL' "$t/out" && [[ -e $t/hold ]] && ok "7. a mark that does not match fails step 6, hold kept" || bad "7. rc=$rc $(cat "$t/out")"

# 8
if [[ $all == *tok-* || $all == *role-id-fake* || $all == *secret-id-fake* ]]; then bad "8. a token or ID shows in the output"
else ok "8. no token or ID in the output"; fi
exit "$fail"
