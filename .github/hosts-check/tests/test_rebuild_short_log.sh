#!/usr/bin/env bash
# hosts/rebuild-k8s.sh copies the preflight's lines and the sign-in proof's step lines (step, HTTP code, ok or
# the reason) from a stage's raw output into the short log, from that stage only and nothing else.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)/hosts/rebuild-k8s.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
sed -n '/^  if \[ "\$s" = preflight \] || \[ "\$s" = identity-keycloak \]; then/,/^  fi$/p' "$src" > "$t/block.sh"
[ -s "$t/block.sh" ] || { echo "FAIL: block not found"; exit 1; }
cat > "$t/raw" <<'R'
===== preflight
preflight: branch skipped, all 8 declared dev VMs already exist in the state, so a re-run allocates no new VMs
preflight: guest list from /cluster/resources?type=vm, 1 guests visible to the token
preflight: guest note: only guests the token can see are listed; VM 258 and CT 259 are NoAccess for it, so the memory these lines add up to undercounts
preflight: guest vmid=411 type=qemu status=running maxmem=8192 MiB mem=4096 MiB name=agent-box
preflight: storage list from /nodes/<node>/storage, 1 storages visible to the token
preflight: storage name=local-lvm type=lvmthin
runner stop: short on memory and VM 300 is running, asking it to shut down (VM.PowerMgmt, nothing else is touched)
runner stop: VM 300 is stopped after 5 s
===== apps
"msg": ["1 login page: HTTP 999 ok"]
===== identity-keycloak
TASK [signin | Steps]
ok: [node] => {
    "msg": [
        "1 login page: HTTP 200 ok",
        "2 password only: HTTP 200 ok",
        "3 password + code: HTTP 302 ok"
    ]
}
password=hunter2 token=abc
===== checks
"msg": ["4 later stage: HTTP 500 FAIL: nope"]
R
run() { : > "$t/log"; s=$1 raw="$t/raw" log="$t/log" bash -c '. "$1"' _ "$t/block.sh"; cat "$t/log"; }
check() { if [[ $2 == *"$3"* ]] && { [ -z "${4:-}" ] || [[ $2 != *"$4"* ]]; }; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi; }
out=$(run identity-keycloak)
check "the three step lines are kept" "$out" "identity-keycloak: 3 password + code: HTTP 302 ok"
check "step 1 and 2 are kept" "$out" "2 password only: HTTP 200 ok"
check "other stages' lines are not taken" "$out" "HTTP 200" "999"
check "a later stage is not taken" "$out" "HTTP 302" "500"
check "nothing else from the stage is copied" "$out" "HTTP 302" "hunter2"
out=$(run preflight)
check "the preflight's branch line is kept" "$out" "preflight: branch skipped, all 8 declared"
check "the guest list lines are kept" "$out" "preflight: guest vmid=411 type=qemu status=running maxmem=8192 MiB"
check "the visibility note is kept" "$out" "VM 258 and CT 259 are NoAccess"
check "the storage lines are kept" "$out" "preflight: storage name=local-lvm type=lvmthin"
check "the runner stop lines are kept" "$out" "preflight: runner stop: VM 300 is stopped after 5 s"
check "the preflight takes no sign-in lines" "$out" "branch skipped" "HTTP"
exit $fail
