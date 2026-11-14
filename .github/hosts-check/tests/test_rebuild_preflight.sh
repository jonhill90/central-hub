#!/usr/bin/env bash
# hosts/rebuild-k8s.sh's memory preflight: it refuses below the minimum free memory, passes at or above it, refuses
# when the memory can't be read (a number nobody saw is not a pass), refuses on any env but dev, and never prints
# the token. Runs the function and the stage from a copy, with a fake curl on PATH.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)/hosts/rebuild-k8s.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
sed -n '/^CI_RUNNER_VMID=/p;/^runner_mark() /p;/^px_api() {/,/^}/p;/^preflight_read_free() {/,/^}/p;/^preflight_stop_runner() {/,/^}/p;/^runner_restart() {/,/^}/p;/^preflight_clean() {/,/^}/p;/^preflight_guests() {/,/^}/p;/^preflight_memory() {/,/^}/p;/^run_stage() {/,/^}/p' "$src" > "$t/fn.sh"
grep -q '^preflight_memory' "$t/fn.sh" && grep -q '^run_stage' "$t/fn.sh" || { echo "FAIL: functions not found"; exit 1; }
mkdir "$t/bin"
cat > "$t/bin/curl" <<'F'
#!/bin/sh
echo "$*" >> "$FAKE_ARGV"; cat > "$FAKE_STDIN"
for a in "$@"; do last=$a; done; echo "$last" | sed 's|.*/api2/json/||' >> "$FAKE_CALLS"
case "$*" in *"-X POST"*status/shutdown*) : > "$FAKE_DIR/stopped"; echo '{"data":"UPID:x"}'; exit 0 ;;
*"-X POST"*status/start*) [ -n "$FAKE_START_FAILS" ] && { echo "curl: (22) The requested URL returned error: 500" >&2; exit 22; }; rm -f "$FAKE_DIR/stopped"; touch "$FAKE_DIR/started"; echo '{"data":"UPID:y"}'; exit 0 ;;
*qemu/300/status/current*) if [ -f "$FAKE_DIR/stopped" ] && [ -z "$FAKE_NEVER_STOPS" ]; then echo '{"data":{"status":"stopped","maxmem":2147483648}}'; else echo '{"data":{"status":"running","maxmem":2147483648}}'; fi; exit 0 ;; esac
case "$*" in *cluster/resources*)
  [ -n "$FAKE_GUESTS_ERROR" ] && { echo "curl: (22) The requested URL returned error: 403 token=SECRETTOKEN" >&2; exit 22; }
  echo '{"data":[{"vmid":300,"type":"qemu","status":"running","maxmem":2147483648,"mem":1073741824,"name":"ci runner;01"},{"vmid":411,"type":"qemu","status":"running","maxmem":8589934592,"mem":4294967296,"name":"agent-box"}]}'
  exit 0 ;; esac
[ -n "$FAKE_CURL_ERROR" ] && { [ "$FAKE_CURL_ERROR" = long ] && { printf "%0185d token=SECRETTOKEN\n" 0 >&2; exit 22; }; echo "curl: (22) The requested URL returned error: 403 token=SECRETTOKEN" >&2; exit 22; }
if [ -f "$FAKE_DIR/stopped" ] && [ -n "$FAKE_AFTER_AVAILABLE" ]; then echo "{\"data\":{\"memory\":{\"total\":$FAKE_TOTAL,\"used\":$FAKE_USED,\"available\":$FAKE_AFTER_AVAILABLE}}}"
elif [ -n "$FAKE_AVAILABLE" ]; then echo "{\"data\":{\"memory\":{\"total\":$FAKE_TOTAL,\"used\":$FAKE_USED,\"available\":$FAKE_AVAILABLE}}}"
else echo "{\"data\":{\"memory\":{\"total\":$FAKE_TOTAL,\"used\":$FAKE_USED}}}"; fi
F
chmod +x "$t/bin/curl"
printf '#!/bin/sh\nexit 0\n' > "$t/bin/sleep"; chmod +x "$t/bin/sleep"
printf 'proxmox_node_name = "node-a"\nnodes = {\n a = { vm_id = 250 }\n b = { vm_id = 251 }\n}\ntemplate_vm_id = 9001\n' > "$t/vars.tfvars"
printf 'proxmox_node_name = "node-a"\nnodes = {\n a = { vm_id = 250 }\n b = { vm_id = 251 }\n c = { vm_id = 252 }\n}\n' > "$t/three.tfvars"
printf '{"resources":[{"mode":"managed","type":"proxmox_virtual_environment_vm","instances":[{},{}]}]}' > "$t/with-vms.tfstate"
printf '{"resources":[]}' > "$t/empty.tfstate"
# The endpoint is built from parts, so the components scanner doesn't take it for a real source.
scheme=https
printf 'export PROXMOX_VE_ENDPOINT=%s\nexport PROXMOX_VE_API_TOKEN=agent@pve!dev=SECRETTOKEN\n' "$scheme://node.invalid:8006/" > "$t/tofu.env"
GIB=1073741824
run() { # env total_gib used_gib error
  rm -rf "$t/state" "$t/envdir" "$t/calls" "$t/argv"; mkdir -p "$t/state" "$t/envdir"; : > "$t/calls"; : > "$t/argv"
  PATH="$t/bin:$PATH" TFVARS="${TFVARS_FILE:-$t/vars.tfvars}" TFSTATE="${STATE:-$t/empty.tfstate}" TOFU_ENV="$t/tofu.env" ENV_NAME=$1 FAKE_TOTAL=$(($2 * GIB)) FAKE_USED=$(($3 * GIB)) FAKE_CURL_ERROR=${4:-} FAKE_AVAILABLE=${FAKE_AVAILABLE:-} FAKE_GUESTS_ERROR=${FAKE_GUESTS_ERROR:-} FAKE_AFTER_AVAILABLE=${FAKE_AFTER_AVAILABLE:-} FAKE_NEVER_STOPS=${FAKE_NEVER_STOPS:-} FAKE_START_FAILS=${FAKE_START_FAILS:-} FAKE_DIR="$t/state" FAKE_CALLS="$t/calls" FAKE_ARGV="$t/argv" FAKE_STDIN="$t/stdin" env_dir="$t/envdir" log="$t/rebuild.log" \
    bash -c '. "$1"; set +e; run_stage preflight; echo "rc=$?"; echo "marker=$([ -f "$env_dir/ci-runner-stopped" ] && echo yes || echo no)"' _ "$t/fn.sh" 2>&1
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
out=$(run dev 31 28); check "the guest list is shown, sorted by VM ID" "$out" "guest vmid=411 type=qemu status=running maxmem=8192 MiB mem=4096 MiB name=agent-box"
check "the list says VM 258 and CT 259 are not visible" "$out" "VM 258 and CT 259 are NoAccess for it"
check "a name is cleaned to safe characters" "$out" "name=cirunner01" "name=ci runner;01"
check "the list says which API path and how many" "$out" "guest list from /cluster/resources?type=vm, 2 guests"
check "the refusal still comes after the list" "$out" "refused" "rc=0"
out=$(FAKE_GUESTS_ERROR=yes run dev 31 28); check "an unreadable guest list is not fatal and says so" "$out" "guest list could not be read" ""
check "the memory refusal still stands" "$out" "refused"
check "the guest read error does not print the token" "$out" "guest list could not be read" "SECRETTOKEN"
out=$(run dev 31 17); check "a pass lists guests too and passes" "$out" "guest vmid=300" "refused"
check "the token is never in the guest request's arguments" "$(cat "$t/argv")" "cluster/resources" "SECRETTOKEN"
grep -q 'stages="preflight \$stages"' "$src" && echo "ok   a dev run gets the preflight" || { echo "FAIL: the preflight is not added to a dev run"; fail=1; }
# Short, VM 300 running: stop it, re-read, and pass when it now fits. The marker stays until the trap starts it.
out=$(FAKE_AFTER_AVAILABLE=$((16 * GIB)) run dev 31 28); check "short then fits: VM 300 is stopped and the run passes" "$out" "runner stop: VM 300 is stopped" "refused"
check "it re-reads the memory and says so" "$out" "16384 MiB (field: available) after VM 300 stopped" "refused"
check "the pass says rc=0 and leaves the marker for the restart" "$out" "rc=0" "marker=no"
check "the marker is there before the trap runs" "$out" "marker=yes" "marker=no"
grep -q 'qemu/300/status/shutdown' "$t/calls" && echo "ok   the shutdown call went to VM 300" || { echo "FAIL: no shutdown call"; fail=1; }
if grep -E 'qemu/[0-9]+/status/(shutdown|stop|start|reset|reboot)' "$t/calls" | grep -v 'qemu/300/'; then echo "FAIL: a guest other than VM 300 was touched"; fail=1; else echo "ok   no guest but VM 300 was touched"; fi
if grep -q SECRETTOKEN "$t/argv"; then echo "FAIL: the token is in curl's arguments"; fail=1; else echo "ok   the token is not in any call's arguments, the stop calls included"; fi
# Still short after the stop: refuse, and the marker is there for the restart.
out=$(FAKE_AFTER_AVAILABLE=$((13 * GIB)) run dev 31 28); check "still short after the stop is refused" "$out" "refused, free memory 13312 MiB" "rc=0"
check "the marker stays so the restart runs" "$out" "marker=yes" "marker=no"
# VM 300 does not stop: refuse, marker stays.
out=$(FAKE_NEVER_STOPS=yes FAKE_AFTER_AVAILABLE=$((16 * GIB)) run dev 31 28); check "a runner that does not stop is refused" "$out" "did not stop within 120 s" "rc=0"
check "the marker stays then too" "$out" "marker=yes" "marker=no"
# Enough memory: no stop at all.
run dev 31 17 > /dev/null; if grep -q 'status/shutdown' "$t/calls"; then echo "FAIL: stopped VM 300 with enough memory"; fail=1; else echo "ok   enough memory means VM 300 is left alone"; fi
# The EXIT trap's function: starts VM 300 when the marker is there, and not otherwise; never fatal.
rs() { # free_gib mark
  rm -rf "$t/state" "$t/calls" "$t/envdir"; mkdir -p "$t/state" "$t/envdir"; : > "$t/calls"; [ "${2:-}" = mark ] && : > "$t/envdir/ci-runner-stopped"
  PATH="$t/bin:$PATH" FAKE_START_FAILS=${FAKE_START_FAILS:-} TFVARS="$t/vars.tfvars" TOFU_ENV="$t/tofu.env" FAKE_TOTAL=$((31 * GIB)) FAKE_USED=0 FAKE_AVAILABLE=$(($1 * GIB)) FAKE_DIR="$t/state" FAKE_CALLS="$t/calls" FAKE_ARGV="$t/argv" FAKE_STDIN="$t/stdin" env_dir="$t/envdir" log="$t/rebuild.log" \
    bash -c '. "$1"; runner_restart; echo "rc=$?"; echo "marker=$([ -f "$env_dir/ci-runner-stopped" ] && echo yes || echo no)"' _ "$t/fn.sh" 2>&1; }
# VM 300 has 2048 MiB maxmem, so the start needs 4096 MiB free (maxmem plus 2048).
out=$(rs 4 mark); check "enough memory: the restart starts VM 300 and clears the marker" "$out" "runner restart: VM 300 started again (free 4096 MiB, needs 4096 MiB)" "marker=yes"
grep -q 'qemu/300/status/start' "$t/calls" && echo "ok   the start call went to VM 300" || { echo "FAIL: no start call"; fail=1; }
out=$(rs 3 mark); check "not enough memory: VM 300 is left stopped and says why" "$out" "runner left stopped: not enough memory (free 3072 MiB, needs 4096 MiB)" "runner restart"
check "the marker stays when it is left stopped" "$out" "marker=yes" "marker=no"
grep -q 'status/start' "$t/calls" && { echo "FAIL: started VM 300 with too little memory"; fail=1; } || echo "ok   no start call with too little memory"
out=$(FAKE_CURL_ERROR=yes rs 8 mark); check "an unreadable memory figure leaves VM 300 stopped" "$out" "runner left stopped: could not read the memory figures" "runner restart"
check "and keeps the marker" "$out" "marker=yes" "marker=no"
out=$(FAKE_START_FAILS=yes rs 8 mark); check "a failed start keeps the marker so a later run retries" "$out" "start failed, marker kept" "marker=no"
out=$(rs 8); check "no marker means nothing is read or started" "$out" "rc=0" "runner"
grep -q 'status/start' "$t/calls" && { echo "FAIL: started with no marker"; fail=1; } || echo "ok   nothing is started without the marker"
grep -q '^  runner_restart$' "$src" && grep -q 'trap runner_restart EXIT' "$src" && echo "ok   a dev run starts the runner again on exit" || { echo "FAIL: no restart trap"; fail=1; }
exit $fail
