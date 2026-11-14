#!/usr/bin/env bash
# roles/openbao/files/openbao-drill.sh against stand-ins for curl, ip, setpriv, install and chown (fake values only),
# from a copy whose fixed paths point into a temporary folder.
#   1. A normal run: 10 steps ok, then the PASS line; the throwaway is stopped and its storage is gone.
#   2. No snapshot: step 2 fails, and nothing is left behind.
#   3. A network device besides lo: step 1 fails before anything starts.
#   4. The throwaway's own token still works after the restore: step 7 fails; the throwaway is stopped, storage gone.
#   5. The login's token lacks policy snapshot: step 9 fails.
#   6. The newest snapshot is the one restored.
#   7. No token or AppRole ID shows in the output.
# Usage: .github/hosts-check/tests/test_openbao_drill.sh   (needs python3)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'pkill -f "sleep 3017" 2>/dev/null || true; rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
mkdir -p "$t/bin" "$t/ids" "$t/snaps" "$t/drill"
printf 'role-id-fake-value' > "$t/ids/role-id"
printf 'secret-id-fake-value' > "$t/ids/secret-id"
: > "$t/tls.crt"
sed -e "s|/var/lib/openbao-drill|$t/drill|g" -e "s|/etc/openbao/snapshot|$t/ids|g" \
    -e "s|/opt/openbao/tls/tls.crt|$t/tls.crt|g" "$root/hosts/ansible/roles/openbao/files/openbao-drill.sh" > "$t/drill.sh"

cat > "$t/bin/ip" <<'SH'
#!/bin/bash
echo "1: lo: <LOOPBACK,UP>"
[[ ${MODE:-} == netdev ]] && echo "2: eth0: <BROADCAST,UP>"
exit 0
SH
cat > "$t/bin/setpriv" <<'SH'
#!/bin/bash
echo $$ > "$T/server.pid"
exec sleep 3017
SH
printf '#!/bin/bash\nfor a; do :; done\nmkdir -p "$a"\n' > "$t/bin/install"
printf '#!/bin/bash\nexit 0\n' > "$t/bin/chown"
cat > "$t/bin/curl" <<'SH'
#!/bin/bash
# The throwaway: phase uninit -> init -> restored, kept in $T/phase.
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
phase=$(cat "$T/phase" 2>/dev/null || echo uninit)
path=${url#*/v1/}
code=200 body=""
case $path in
  sys/health) case $phase in uninit) code=501 ;; *) code=200 ;; esac ;;
  sys/init) echo init > "$T/phase"; body='{"root_token": "tok-root-secret"}' ;;
  sys/storage/raft/snapshot-force)
    if [[ $tok == tok-root-secret && -s ${data#@} ]]; then echo restored > "$T/phase"; echo "${data#@}" > "$T/restored"; code=204
    else code=403; fi ;;
  auth/approle/login)
    if [[ $body_in == '{"role_id": "role-id-fake-value", "secret_id": "secret-id-fake-value"}' && $phase == restored ]]; then
      body='{"auth": {"client_token": "tok-snap-secret"}}'
    else code=400; body='{"errors": ["invalid"]}'; fi ;;
  auth/token/lookup-self)
    if [[ $tok == tok-root-secret ]]; then
      if [[ $phase == restored && ${MODE:-} != stale ]]; then code=403; fi
    elif [[ $tok == tok-snap-secret ]]; then
      if [[ ${MODE:-} == nopolicy ]]; then body='{"data": {"policies": ["default"]}}'
      else body='{"data": {"policies": ["default", "snapshot"]}}'; fi
    else code=403; fi ;;
  auth/token/revoke-self) code=204 ;;
  *) code=404 ;;
esac
[[ -n $out ]] || printf '%s' "$body"
[[ -n $fmt ]] && printf '%s' "$code"
exit 0
SH
chmod +x "$t/bin/"*

run() { # mode
  rm -f "$t/phase" "$t/restored" "$t/server.pid"
  MODE=$1 T=$t PATH="$t/bin:$PATH" bash "$t/drill.sh" 8300 "$t/snaps" 3 > "$t/out" 2>&1 && rc=0 || rc=$?
}
gone() { [[ ! -e $t/drill/raft ]] && { [[ ! -s $t/server.pid ]] || ! kill -0 "$(cat "$t/server.pid")" 2>/dev/null; }; }

echo old > "$t/snaps/raft-20261114T090000Z.snap"; touch -d '2 hours ago' "$t/snaps/raft-20261114T090000Z.snap"
echo new > "$t/snaps/raft-20261114T110000Z.snap"
run normal
if [[ $rc -eq 0 && $(grep -c ' ok' "$t/out") -eq 10 ]] && grep -q '^PASS: restore drill: raft-20261114T110000Z.snap' "$t/out" && gone; then
  ok "1. a normal run passes 10 steps, prints PASS, and leaves no throwaway"
else bad "1. rc=$rc $(cat "$t/out")"; fi
[[ $(cat "$t/restored" 2>/dev/null) == "$t/snaps/raft-20261114T110000Z.snap" ]] && ok "6. the newest snapshot is restored" || bad "6. restored: $(cat "$t/restored" 2>/dev/null)"
if grep -qE 'tok-|role-id-fake|secret-id-fake' "$t/out"; then bad "7. a token or ID shows in the output"; else ok "7. no token or ID in the output"; fi

mkdir -p "$t/empty"
rm -f "$t/phase"
MODE=normal T=$t PATH="$t/bin:$PATH" bash "$t/drill.sh" 8300 "$t/empty" 3 > "$t/out" 2>&1 && rc=0 || rc=$?
[[ $rc -ne 0 ]] && grep -q '2 snapshot FAIL' "$t/out" && gone && ok "2. no snapshot fails step 2 and leaves nothing" || bad "2. rc=$rc $(cat "$t/out")"

run netdev
[[ $rc -ne 0 ]] && grep -q '1 only loopback FAIL' "$t/out" && [[ ! -e $t/server.pid ]] && ok "3. a device besides lo fails step 1 before anything starts" || bad "3. rc=$rc $(cat "$t/out")"

run stale
[[ $rc -ne 0 ]] && grep -q '7 old token refused FAIL' "$t/out" && gone && ok "4. the throwaway's own token still working fails step 7; throwaway stopped, storage gone" || bad "4. rc=$rc $(cat "$t/out")"

run nopolicy
[[ $rc -ne 0 ]] && grep -q '9 its policy FAIL' "$t/out" && gone && ok "5. a token without policy snapshot fails step 9" || bad "5. rc=$rc $(cat "$t/out")"
exit "$fail"
