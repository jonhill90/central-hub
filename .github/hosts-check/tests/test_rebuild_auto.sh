#!/usr/bin/env bash
# The dev rebuild's timer run (hosts/ansible/roles/agent_box/files/rebuild.sh auto, auto_decide), against a real git
# repository and real log files, with a stand-in hosts/rebuild-k8s.sh for the fit check:
#   1. The newest full run already built main's head, passed or not: nothing starts.
#   2. Nothing under hosts/ changed since the newest full pass: nothing starts; a change there: it goes on.
#   3. No full pass logged, or the pass's commit is not on main: it goes on.
#   4. Teardown-only and identity-only logs are not full runs; a full run that did not pass is not a pass.
#   5. The fit check: it gets the dev settings with PREFLIGHT_KEEP_DESKTOP=true and the short-node setting; a fit that
#      fails stops it, with the preflight's reason.
#   6. Dev is up (VMs in the dev state, or the state can't be read): nothing starts, before the fit check.
#   7. The wrapper: `auto` takes no argument, exits 0 when the lock is held, has no sudo line, and its run keeps the
#      desktop running; the role installs the timer.
# Usage: .github/hosts-check/tests/test_rebuild_auto.sh   (needs git)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
src=$root/hosts/ansible/roles/agent_box/files/rebuild.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

sed -n '/^fit_check() {/,/^}/p;/^LAB_TEST_QUIET_MIN=/p;/^lab_test_busy() {/,/^}/p;/^auto_decide() {/,/^}/p' "$src" > "$t/fn.sh"
grep -q 'rebuild-k8s.sh" "$fitdir" --fit' "$t/fn.sh" && grep -q '^auto_decide() {' "$t/fn.sh" && grep -q '^lab_test_busy() {' "$t/fn.sh" || { echo "FAIL: fit_check and auto_decide were not found in rebuild.sh"; exit 1; }

g() { git -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main "$@"; }
g init -q "$t/repo"
mkdir -p "$t/repo/hosts" "$t/repo/docs"
# The stand-in fit check: records its settings file, answers with FIT_RC.
printf '%s\n' '#!/bin/bash' 'cp "$1/rebuild.env" "$FIT_SEEN"' 'echo "preflight: refused, estimate 9216 MiB is below 11008 MiB"' 'exit "${FIT_RC:-0}"' > "$t/repo/hosts/rebuild-k8s.sh"
(cd "$t/repo" && g add -A && g commit -q -m c1 &&
 echo a > hosts/a && g add -A && g commit -q -m c2 &&
 echo d > docs/d && g add -A && g commit -q -m c3 &&
 echo b > hosts/b && g add -A && g commit -q -m c4)
c2=$(git -C "$t/repo" rev-parse HEAD~2) c3=$(git -C "$t/repo" rev-parse HEAD~1) c4=$(git -C "$t/repo" rev-parse HEAD)

envdir=$t/env work=$t/work keys=$t/keys
mkdir -p "$envdir/logs" "$work/state"
logf() { # name commit kind: pass | fail | teardown | identity
  local f=$envdir/logs/rebuild-$1.log
  case $3 in
    teardown) printf '%s\n' "rebuild: central-hub $2" "2026-11-18T01:00:00Z teardown start" "2026-11-18T01:00:20Z teardown end rc=0 20s" "rebuild: all stages passed" > "$f" ;;
    identity) printf '%s\n' "rebuild: central-hub $2" "2026-11-18T01:00:00Z identity-keycloak start" "2026-11-18T01:03:00Z identity-keycloak end rc=0 180s" "rebuild: all stages passed" > "$f" ;;
    pass) printf '%s\n' "rebuild: central-hub $2" "2026-11-18T01:00:00Z vms start" "2026-11-18T01:01:00Z vms end rc=0 60s" "2026-11-18T01:10:00Z checks start" "2026-11-18T01:13:00Z checks end rc=0 180s" "rebuild: all stages passed" > "$f" ;;
    fail) printf '%s\n' "rebuild: central-hub $2" "2026-11-18T01:00:00Z vms start" "2026-11-18T01:01:00Z vms end rc=0 60s" "2026-11-18T01:02:00Z cluster start" "2026-11-18T01:09:00Z cluster end rc=2 420s" > "$f" ;;
  esac
}
decide() { # prints the output, then rc= on its own line
  FIT_SEEN=$t/fit-seen FIT_RC=${FIT_RC:-0} repo=$t/repo envdir=$envdir work=$work keys=$keys inventory="$t/env/inventory" \
    bash -c '. "$1"; auto_decide; echo "rc=$?"' _ "$t/fn.sh" 2>&1
}
reset() { rm -f "$envdir"/logs/* "$t/fit-seen" "$work/short-node"; }

# 1
reset; logf 20261118T010000Z "$c4" pass; o1a=$(decide)
reset; logf 20261118T010000Z "$c2" pass; logf 20261118T020000Z "$c4" fail; o1b=$(decide)
if [[ $o1a == *"already built main's head ${c4:0:7} (passed); nothing started"*"rc=1" && ! -e $t/fit-seen &&
      $o1b == *"already built main's head ${c4:0:7} (did not pass); nothing started"*"rc=1" ]]; then
  ok "1. the newest full run already built main's head (passed or not): nothing starts, no fit check"
else bad "1. $o1a | $o1b"; fi

# 2
reset; logf 20261118T010000Z "$c2" pass
o2a=$(cd "$t/repo" && git checkout -q "$c3" && cd / && decide)
git -C "$t/repo" checkout -q main
reset; logf 20261118T010000Z "$c2" pass; o2b=$(decide)
if [[ $o2a == *"nothing under hosts/ changed since the newest full pass at ${c2:0:7}"*"rc=1" &&
      $o2b == *"1 files under hosts/ changed since the newest full pass at ${c2:0:7}"*"building main's head ${c4:0:7}"*"rc=0" ]]; then
  ok "2. no change under hosts/ since the newest full pass: nothing starts; a change there: it builds"
else bad "2. $o2a | $o2b"; fi

# 3
reset; o3a=$(decide)
reset; logf 20261118T010000Z 0123456789abcdef0123456789abcdef01234567 pass; o3b=$(decide)
if [[ $o3a == *"no full pass on main is logged, so main's head is built"*"rc=0" && $o3b == *"no full pass on main is logged"*"rc=0" ]]; then
  ok "3. no full pass logged, or its commit not on main: it builds"
else bad "3. $o3a | $o3b"; fi

# 4
reset; logf 20261118T010000Z "$c2" pass; logf 20261118T020000Z "$c4" teardown; logf 20261118T030000Z "$c4" identity
logf 20261118T005000Z "$c3" fail; o4a=$(decide)
reset; logf 20261118T010000Z "$c3" pass; logf 20261118T020000Z "$c3" fail; o4b=$(decide)
if [[ $o4a == *"1 files under hosts/ changed since the newest full pass at ${c2:0:7}"*"rc=0" &&
      $o4b == *"1 files under hosts/ changed since the newest full pass at ${c3:0:7}"*"rc=0" ]]; then
  ok "4. teardown-only and identity-only runs at main's head are not full runs; a failed full run is not a pass"
else bad "4. $o4a | $o4b"; fi

# 5
reset; echo ephemeral-dev > "$work/short-node"; o5a=$(decide); s5a=$(cat "$t/fit-seen" 2>/dev/null)
reset; echo something-else > "$work/short-node"; o5b=$(decide); s5b=$(cat "$t/fit-seen" 2>/dev/null)
reset; o5c=$(FIT_RC=3 decide)
if [[ $o5a == *"rc=0" && $s5a == *"ENV_NAME=dev"* && $s5a == *"PREFLIGHT_KEEP_DESKTOP=true"* && $s5a == *"PREFLIGHT_SHORT_NODE=ephemeral-dev"* &&
      $s5a == *"TFVARS=$keys/dev-vms.tfvars"* && $s5a == *"VM_ID_MAX=257"* &&
      $o5b == *"rc=0" && $s5b != *PREFLIGHT_SHORT_NODE* &&
      $o5c == *"the memory preflight does not fit now (preflight: refused, estimate 9216 MiB is below 11008 MiB); nothing started"*"rc=1" &&
      $(stat -c %a "$work/state/rebuild-fit") == 700 && $(stat -c %a "$work/state/rebuild-fit/rebuild.env") == 600 ]]; then
  ok "5. the fit check gets dev's settings, keeps the desktop, carries a valid short-node setting only; a failed fit stops it with the reason"
else bad "5. $o5a [$s5a] | $o5b [$s5b] | $o5c"; fi

# 6
reset; printf '{"resources":[{"mode":"managed","type":"proxmox_virtual_environment_vm","instances":[{},{}]}]}' > "$work/state/dev-vms.tfstate"
o7a=$(decide); s7a=$([ -e "$t/fit-seen" ] && echo fit || echo nofit)
reset; echo 'not json' > "$work/state/dev-vms.tfstate"; o7b=$(decide)
reset; printf '{"resources":[]}' > "$work/state/dev-vms.tfstate"; o7c=$(decide)
rm -f "$work/state/dev-vms.tfstate"
if [[ $o7a == *"dev is up (2 VMs in the dev state)"*"nothing started"*"rc=1" && $s7a == nofit &&
      $o7b == *"dev is up (unreadable VMs in the dev state)"*"rc=1" && $o7c == *"rc=0" ]]; then
  ok "6. dev up (VMs in the dev state, or a state that can't be read): nothing starts, no fit check; an empty state goes on"
else bad "6. $o7a [$s7a] | $o7b | $o7c"; fi

# 7
bash "$src" auto extra > "$t/out" 2>&1; r6a=$?
defaults=$root/hosts/ansible/roles/agent_box/defaults/main.yml
if [[ $r6a -eq 2 ]] && grep -q 'usage: rebuild .*|auto' "$t/out" &&
   grep -q '\[\[ \$action != auto \]\] || { echo "rebuild auto: a rebuild run (dev or prod) is going; nothing started"; exit 0; }' "$src" &&
   grep -q '^\$keep_desktop_env$' "$src" && grep -q 'keep_desktop_env="PREFLIGHT_KEEP_DESKTOP=true"' "$src" &&
   grep -q 'if \[\[ \$action == auto \]\]; then auto_decide || exit 0; fi' "$src" &&
   ! grep -A3 '^  - name: rebuild$' "$defaults" | grep -q 'auto' &&
   grep -q '^agent_box_rebuild_auto: true$' "$defaults" &&
   grep -q 'ExecStart={{ agent_box_libexec_dir }}/rebuild.sh auto$' "$root/hosts/ansible/roles/agent_box/templates/rebuild-auto.service.j2"; then
  ok "7. auto takes no argument, exits 0 while a run holds the lock, has no sudo line, keeps the desktop; the role installs its timer"
else bad "7. $r6a $(cat "$t/out")"; fi

# 8: the fit action: the fit check's lines, then the 12 running guests with the most memory, read-only. A stand-in
# curl returns a fixed guest list; the exit code is the fit check's.
sed -n '/^if \[\[ \${1:-} == fit && \$# -eq 1 \]\]; then$/,/^fi$/p' "$src" > "$t/fitact.sh"
grep -q 'exit $(( rc == 0' "$t/fitact.sh" || bad "8. the fit action was not found in rebuild.sh"
sed -n '/^fit_check() {/,/^}/p' "$src" > "$t/fitfn.sh"
mkdir -p "$t/keys8" "$t/bin8"
echo 'PROXMOX_VE_API_TOKEN=x' > "$t/keys8/proxmox-dev.env"; echo 'x = 1' > "$t/keys8/dev-vms.tfvars"
printf '%s\n' '#!/bin/bash' 'cat > /dev/null' 'echo "{\"data\": [{\"vmid\": 100, \"name\": \"small\", \"status\": \"running\", \"mem\": 1073741824, \"maxmem\": 2147483648}, {\"vmid\": 258, \"name\": \"big\", \"status\": \"running\", \"mem\": 8589934592, \"maxmem\": 8589934592}, {\"vmid\": 300, \"name\": \"off\", \"status\": \"stopped\", \"mem\": 0, \"maxmem\": 1}]}"' > "$t/bin8/curl"
chmod +x "$t/bin8/curl"
fitact() { FIT_SEEN=$t/fit-seen8 FIT_RC=$1 repo=$t/repo work=$t/work8 keys=$t/keys8 inventory="$t/env/inventory" PATH=$t/bin8:$PATH \
  bash -c 'mkdir -p "$work"; . "$1"; f=$2; set -- fit; . "$f"' _ "$t/fitfn.sh" "$t/fitact.sh" 2>&1; echo "rc=$?"; }
o8a=$(fitact 0); o8b=$(fitact 3)
# An older checkout: the stand-in dies on --fit as rebuild-k8s.sh did before #635.
cp "$t/repo/hosts/rebuild-k8s.sh" "$t/rk8s.keep"
printf '%s\n' '#!/bin/bash' 'echo "rebuild-k8s: unknown argument: --fit" >&2' 'exit 2' > "$t/repo/hosts/rebuild-k8s.sh"
o8c=$(fitact 0)
cp "$t/rk8s.keep" "$t/repo/hosts/rebuild-k8s.sh"
if [[ $o8a == *"preflight: refused, estimate 9216 MiB"* && $o8a == *"vmid=258 name=big status=running mem=8192 of 8192 MiB"* &&
      $o8a != *"name=off"* && $o8a == *"rc=0" && $o8b == *"rc=3" && $o8b == *"vmid=258"* &&
      $o8a == *"fit: checkout "* && $o8c == *"older than the --fit flag"* && $o8a != *"older than the --fit flag"* ]]; then
  ok "8. fit prints the fit check's lines and the running guests by memory, biggest first, and exits with the fit check's code"
else bad "8. [$o8a] [$o8b] [$o8c]"; fi

# 9: lab-test comes first. Each gate stops the tick with its own line before the fit check: the lock held (a probe,
# the lock is free again after it), a state that holds a VM or can't be read, a log written less than 60 minutes
# ago. With none of them, or a log older than the window and an empty state, it goes on. The states have the shape
# tofu writes for hosts/terraform/home/lab-test: after destroy only the installer ISO stays (lab-test.sh, destroy),
# which is an idle lab-test; with the copy built, VM 256 is there too.
lt=$work/state; mkdir -p "$lt"
rm -f "$lt"/lab-test.*
reset; logf 20261118T010000Z "$c2" pass
: > "$lt/lab-test.lock"
( exec 9> "$lt/lab-test.lock"; flock -n 9 && sleep 4 ) & sleep 1
o9a=$(decide); wait
o9a2=$(decide)
rm -f "$lt/lab-test.lock" "$t/fit-seen"
iso='{"mode": "managed", "type": "proxmox_virtual_environment_file", "name": "installer", "instances": [{"attributes": {"id": "local:iso/lab-test-256-pve-auto-ecf64d480ea7.iso"}}]}'
vm='{"mode": "managed", "type": "proxmox_virtual_environment_vm", "name": "host", "instances": [{"attributes": {"vm_id": 256}}]}'
echo "{\"version\": 4, \"resources\": [$iso, $vm]}" > "$lt/lab-test.tfstate"; o9b=$(decide)
echo 'not json' > "$lt/lab-test.tfstate"; o9c=$(decide)
echo '{"resources": []}' > "$lt/lab-test.tfstate"; : > "$lt/lab-test.log"; o9d=$(decide)
touch -d '2 hours ago' "$lt/lab-test.log"; rm -f "$t/fit-seen"; o9e=$(decide)
fit9e=no; [[ ! -e $t/fit-seen ]] || fit9e=yes
echo "{\"version\": 4, \"resources\": [$iso]}" > "$lt/lab-test.tfstate"; rm -f "$t/fit-seen"; o9f=$(decide); fit9f=no; [[ ! -e $t/fit-seen ]] || fit9f=yes
if [[ $o9a == *"a lab-test run holds its lock; nothing started"*"rc=1" && $o9a2 != *"holds its lock"* &&
      $o9b == *"lab-test state holds 1 VM resources"*"rc=1" && $o9c == *"lab-test state holds unreadable VM resources"*"rc=1" &&
      $o9d == *"wrote its log 0 minutes ago, inside the 60-minute quiet window; nothing started"*"rc=1" &&
      $o9e == *"building main's head"*"rc=0" && $fit9e == yes &&
      $o9f != *"lab-test state holds"* && $o9f == *"building main's head"*"rc=0" && $fit9f == yes ]]; then
  ok "9. the timer skips for a held lab-test lock, a state with VM 256 or unreadable, and a log under 60 minutes old, each with its own line; an idle lab-test, or a state with only the kept installer ISO, lets it go on"
else bad "9. [$o9a] [$o9a2] [$o9b] [$o9c] [$o9d] [$o9e] [$o9f]"; fi
rm -f "$lt"/lab-test.*

exit $fail
