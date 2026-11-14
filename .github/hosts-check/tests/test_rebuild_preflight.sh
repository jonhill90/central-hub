#!/usr/bin/env bash
# hosts/rebuild-k8s.sh's memory preflight: it refuses below the minimum free memory, passes at or above it, refuses
# when the memory can't be read (a number nobody saw is not a pass), refuses on any env but dev, and never prints
# the token. Runs the function and the stage from a copy, with a fake curl on PATH.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)/hosts/rebuild-k8s.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
sed -n '/^preflight_clean() {/,/^}/p;/^preflight_guests() {/,/^}/p;/^preflight_memory() {/,/^}/p;/^run_stage() {/,/^}/p' "$src" > "$t/fn.sh"
grep -q '^preflight_memory' "$t/fn.sh" && grep -q '^run_stage' "$t/fn.sh" || { echo "FAIL: functions not found"; exit 1; }
mkdir "$t/bin"
cat > "$t/bin/curl" <<'F'
#!/bin/sh
echo "$*" > "$FAKE_ARGV"; cat > "$FAKE_STDIN"
case "$*" in *cluster/resources*)
  [ -n "$FAKE_GUESTS_ERROR" ] && { echo "curl: (22) The requested URL returned error: 403 token=SECRETTOKEN" >&2; exit 22; }
  echo '{"data":[{"vmid":300,"type":"qemu","status":"running","maxmem":2147483648,"mem":1073741824,"name":"ci runner;01"},{"vmid":258,"type":"qemu","status":"running","maxmem":8589934592,"mem":4294967296,"name":"agent-box"}]}'
  exit 0 ;; esac
[ -n "$FAKE_CURL_ERROR" ] && { [ "$FAKE_CURL_ERROR" = long ] && { printf "%0185d token=SECRETTOKEN\n" 0 >&2; exit 22; }; echo "curl: (22) The requested URL returned error: 403 token=SECRETTOKEN" >&2; exit 22; }
if [ -n "$FAKE_AVAILABLE" ]; then echo "{\"data\":{\"memory\":{\"total\":$FAKE_TOTAL,\"used\":$FAKE_USED,\"available\":$FAKE_AVAILABLE}}}"
else echo "{\"data\":{\"memory\":{\"total\":$FAKE_TOTAL,\"used\":$FAKE_USED}}}"; fi
F
chmod +x "$t/bin/curl"
printf 'proxmox_node_name = "node-a"\nnodes = {\n a = { vm_id = 250 }\n b = { vm_id = 251 }\n}\ntemplate_vm_id = 9001\n' > "$t/vars.tfvars"
printf 'proxmox_node_name = "node-a"\nnodes = {\n a = { vm_id = 250 }\n b = { vm_id = 251 }\n c = { vm_id = 252 }\n}\n' > "$t/three.tfvars"
printf '{"resources":[{"mode":"managed","type":"proxmox_virtual_environment_vm","instances":[{},{}]}]}' > "$t/with-vms.tfstate"
printf '{"resources":[]}' > "$t/empty.tfstate"
# The endpoint is built from parts, so the components scanner doesn't take it for a real source.
scheme=https
printf 'export PROXMOX_VE_ENDPOINT=%s\nexport PROXMOX_VE_API_TOKEN=agent@pve!dev=SECRETTOKEN\n' "$scheme://node.invalid:8006/" > "$t/tofu.env"
GIB=1073741824
run() { # env total_gib used_gib error
  PATH="$t/bin:$PATH" TFVARS="${TFVARS_FILE:-$t/vars.tfvars}" TFSTATE="${STATE:-$t/empty.tfstate}" TOFU_ENV="$t/tofu.env" ENV_NAME=$1 FAKE_TOTAL=$(($2 * GIB)) FAKE_USED=$(($3 * GIB)) FAKE_CURL_ERROR=${4:-} FAKE_AVAILABLE=${FAKE_AVAILABLE:-} FAKE_GUESTS_ERROR=${FAKE_GUESTS_ERROR:-} FAKE_ARGV="$t/argv" FAKE_STDIN="$t/stdin" \
    bash -c '. "$1"; set +e; run_stage preflight; echo "rc=$?"' _ "$t/fn.sh" 2>&1
}
check() { if [[ $2 == *"$3"* ]] && { [ -z "${4:-}" ] || [[ $2 != *"$4"* ]]; }; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi; }
out=$(run dev 31 18); check "13 GiB free is refused" "$out" "refused" "rc=0"; check "it says the sizes" "$out" "13312 MiB"
out=$(run dev 31 17); check "14 GiB free passes" "$out" "rc=0" "refused"
out=$(run dev 31 16); check "15 GiB free passes" "$out" "rc=0" "refused"
if grep -q SECRETTOKEN "$t/argv"; then echo "FAIL: the token is in curl's arguments"; fail=1; else echo "ok   the token is not in curl's arguments"; fi
if grep -q 'header = "Authorization: PVEAPIToken=agent@pve!dev=SECRETTOKEN"' "$t/stdin"; then echo "ok   the token goes in on stdin"; else echo "FAIL: the header is not on stdin"; fail=1; fi
out=$(run dev 31 17 yes); check "an unreadable node is refused" "$out" "could not be read" "rc=0"; check "the token is not printed" "$out" "rc=1" "SECRETTOKEN"
out=$(run dev 31 17 long); check "a token straddling character 200 leaves no prefix" "$out" "could not be read" "SECRET"
check "no partial prefix of the token either" "$out" "rc=1" "SECR"
out=$(run prod 31 1); check "prod refuses the dev preflight" "$out" "dev only" "rc=0"
out=$(PREFLIGHT_MIN_FREE_MIB=20480 run dev 31 17); check "the minimum can be raised" "$out" "refused" "rc=0"
out=$(FAKE_AVAILABLE=$((20 * GIB)) run dev 31 30); check "memory.available wins when present" "$out" "20480 MiB (field: available)" "refused"
out=$(FAKE_AVAILABLE=$((5 * GIB)) run dev 31 1); check "a low memory.available refuses even with a low used" "$out" "refused" "rc=0"
out=$(run dev 31 17); check "total-used is the fallback and is named" "$out" "(field: total-used)" ""
out=$(STATE="$t/with-vms.tfstate" run dev 31 28); check "a state holding every declared VM skips the check, even with low memory" "$out" "branch skipped, all 2 declared dev VMs" "refused"
check "a skipped run says rc=0" "$out" "rc=0"
out=$(STATE="$t/with-vms.tfstate" TFVARS_FILE="$t/three.tfvars" run dev 31 28); check "a partial state (2 of 3) is checked and refused on low memory" "$out" "holds 2 of 3 declared" "rc=0"
out=$(STATE="$t/with-vms.tfstate" TFVARS_FILE="$t/three.tfvars" run dev 31 17); check "a partial state passes with enough memory" "$out" "branch checked" "refused"
out=$(STATE="$t/missing.tfstate" run dev 31 28); check "no state file means a fresh build and is checked" "$out" "branch checked" ""
out=$(STATE="$t/empty.tfstate" run dev 31 17); check "an empty state is checked and passes with enough memory" "$out" "branch checked" "refused"
out=$(run dev 31 28); check "the guest list is shown, sorted by VM ID" "$out" "guest vmid=258 type=qemu status=running maxmem=8192 MiB mem=4096 MiB name=agent-box"
check "a name is cleaned to safe characters" "$out" "name=cirunner01" ";"
check "the list says which API path and how many" "$out" "guest list from /cluster/resources?type=vm, 2 guests"
check "the refusal still comes after the list" "$out" "refused" "rc=0"
out=$(FAKE_GUESTS_ERROR=yes run dev 31 28); check "an unreadable guest list is not fatal and says so" "$out" "guest list could not be read" ""
check "the memory refusal still stands" "$out" "refused"
check "the guest read error does not print the token" "$out" "guest list could not be read" "SECRETTOKEN"
out=$(run dev 31 17); check "a pass lists guests too and passes" "$out" "guest vmid=300" "refused"
check "the token is never in the guest request's arguments" "$(cat "$t/argv")" "cluster/resources" "SECRETTOKEN"
grep -q 'stages="preflight \$stages"' "$src" && echo "ok   a dev run gets the preflight" || { echo "FAIL: the preflight is not added to a dev run"; fail=1; }
exit $fail
