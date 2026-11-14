#!/usr/bin/env bash
# hosts/rebuild-k8s.sh's memory preflight: it refuses below the minimum free memory, passes at or above it, refuses
# when the memory can't be read (a number nobody saw is not a pass), refuses on any env but dev, and never prints
# the token. Runs the function and the stage from a copy, with a fake curl on PATH.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)/hosts/rebuild-k8s.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
sed -n '/^preflight_memory() {/,/^}/p;/^run_stage() {/,/^}/p' "$src" > "$t/fn.sh"
grep -q '^preflight_memory' "$t/fn.sh" && grep -q '^run_stage' "$t/fn.sh" || { echo "FAIL: functions not found"; exit 1; }
mkdir "$t/bin"
cat > "$t/bin/curl" <<'F'
#!/bin/sh
echo "$*" > "$FAKE_ARGV"; cat > "$FAKE_STDIN"
[ -n "$FAKE_CURL_ERROR" ] && { echo "curl: (22) The requested URL returned error: 403 token=SECRETTOKEN" >&2; exit 22; }
if [ -n "$FAKE_AVAILABLE" ]; then echo "{\"data\":{\"memory\":{\"total\":$FAKE_TOTAL,\"used\":$FAKE_USED,\"available\":$FAKE_AVAILABLE}}}"
else echo "{\"data\":{\"memory\":{\"total\":$FAKE_TOTAL,\"used\":$FAKE_USED}}}"; fi
F
chmod +x "$t/bin/curl"
printf 'proxmox_node_name = "node-a"\n' > "$t/vars.tfvars"
printf 'export PROXMOX_VE_ENDPOINT=https://pve.example:8006/\nexport PROXMOX_VE_API_TOKEN=agent@pve!dev=SECRETTOKEN\n' > "$t/tofu.env"
GIB=1073741824
run() { # env total_gib used_gib error
  PATH="$t/bin:$PATH" TFVARS="$t/vars.tfvars" TOFU_ENV="$t/tofu.env" ENV_NAME=$1 FAKE_TOTAL=$(($2 * GIB)) FAKE_USED=$(($3 * GIB)) FAKE_CURL_ERROR=${4:-} FAKE_AVAILABLE=${FAKE_AVAILABLE:-} FAKE_ARGV="$t/argv" FAKE_STDIN="$t/stdin" \
    bash -c '. "$1"; set +e; run_stage preflight; echo "rc=$?"' _ "$t/fn.sh" 2>&1
}
check() { if [[ $2 == *"$3"* ]] && { [ -z "${4:-}" ] || [[ $2 != *"$4"* ]]; }; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi; }
out=$(run dev 31 18); check "13 GiB free is refused" "$out" "refused" "rc=0"; check "it says the sizes" "$out" "13312 MiB"
out=$(run dev 31 17); check "14 GiB free passes" "$out" "rc=0" "refused"
out=$(run dev 31 16); check "15 GiB free passes" "$out" "rc=0" "refused"
if grep -q SECRETTOKEN "$t/argv"; then echo "FAIL: the token is in curl's arguments"; fail=1; else echo "ok   the token is not in curl's arguments"; fi
if grep -q 'header = "Authorization: PVEAPIToken=agent@pve!dev=SECRETTOKEN"' "$t/stdin"; then echo "ok   the token goes in on stdin"; else echo "FAIL: the header is not on stdin"; fail=1; fi
out=$(run dev 31 17 yes); check "an unreadable node is refused" "$out" "could not be read" "rc=0"; check "the token is not printed" "$out" "rc=1" "SECRETTOKEN"
out=$(run prod 31 1); check "prod refuses the dev preflight" "$out" "dev only" "rc=0"
out=$(PREFLIGHT_MIN_FREE_MIB=20480 run dev 31 17); check "the minimum can be raised" "$out" "refused" "rc=0"
out=$(FAKE_AVAILABLE=$((20 * GIB)) run dev 31 30); check "memory.available wins when present" "$out" "20480 MiB (field: available)" "refused"
out=$(FAKE_AVAILABLE=$((5 * GIB)) run dev 31 1); check "a low memory.available refuses even with a low used" "$out" "refused" "rc=0"
out=$(run dev 31 17); check "total-used is the fallback and is named" "$out" "(field: total-used)" ""
grep -q 'stages="preflight \$stages"' "$src" && echo "ok   a dev run gets the preflight" || { echo "FAIL: the preflight is not added to a dev run"; fail=1; }
exit $fail
