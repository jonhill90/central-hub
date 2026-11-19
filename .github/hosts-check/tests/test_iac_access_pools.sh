#!/usr/bin/env bash
# iac-access.sh runs twice on a copy host (lab-test.sh, host stage), and on an empty host VM 100 and CT 900 do not
# exist yet. Proxmox keeps a pool's member for a guest that is gone, but GET /pools/<id> lists only guests that
# exist (pve-manager PVE/API2/Pool.pm), and `pvesh set` stops when the member is stored. So the second run must not
# set a pool member for a missing guest. This runs the real script with stand-in pveum, pvesh and hostname that
# behave that way; the real host (the guests exist) must still move them into their pools, once.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
script=$root/hosts/terraform/home/bootstrap/iac-access.sh
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
mkdir -p "$w/bin"
cat > "$w/bin/hostname" <<'S'
#!/bin/sh
echo pvetest
S
# pveum: every list says everything exists, so only the pool moves are under test.
cat > "$w/bin/pveum" <<'S'
#!/bin/sh
case "$*" in
  *" list "*|*" list") echo '[{"groupid":"iac","roleid":"IacOps","userid":"iac@pve","tokenid":"apply","poolid":"firewall"},{"poolid":"remote-access"},{"poolid":"k8s"}]' ;;
esac
exit 0
S
# pvesh: $STATE holds "pool id" lines (stored members), $GUESTS holds the ids of guests that exist.
cat > "$w/bin/pvesh" <<'S'
#!/bin/bash
case "$1 $2" in
  "get /cluster/resources")
    printf '['; sep=; while read -r id; do printf '%s{"id":"qemu/%s","type":"qemu","vmid":%s,"node":"pvetest"}' "$sep" "$id" "$id"; sep=,; done < "$GUESTS"; printf ']\n' ;;
  "get /pools/"*)
    pool=${2#/pools/}; printf '{"members":['; sep=
    while read -r p id; do
      [ "$p" = "$pool" ] && grep -qx "$id" "$GUESTS" && { printf '%s{"vmid":%s}' "$sep" "$id"; sep=,; }
    done < "$STATE"; printf ']}\n' ;;
  "set /pools/"*)
    pool=${2#/pools/}; id=$4
    grep -qx "$pool $id" "$STATE" && { echo "update pools failed: VM $id is already a pool member" >&2; exit 255; }
    echo "$pool $id" >> "$STATE" ;;
  *) echo "pvesh stand-in: unexpected $*" >&2; exit 2 ;;
esac
S
chmod +x "$w/bin/"*
fail=0
run() { # <label> <guests...>: run the script twice with these guests, report both exits and the stored members
  local label=$1; shift
  : > "$w/state"; printf '%s\n' "$@" > "$w/guests"
  local rc1=0 rc2=0
  PATH="$w/bin:$PATH" STATE="$w/state" GUESTS="$w/guests" sh "$script" >"$w/out1" 2>&1 || rc1=$?
  PATH="$w/bin:$PATH" STATE="$w/state" GUESTS="$w/guests" sh "$script" >"$w/out2" 2>&1 || rc2=$?
  echo "$label: run 1 exit $rc1, run 2 exit $rc2, stored: $(tr '\n' ';' < "$w/state")"
  cat "$w/out2" | grep -i "failed" || true
  RC1=$rc1; RC2=$rc2
}
run "empty host (no guests)" ""
if [ "$RC1" = 0 ] && [ "$RC2" = 0 ] && [ ! -s "$w/state" ]; then echo "ok   an empty host: both runs pass and no member is stored for a missing guest"
else echo "not ok  an empty host: both runs must pass and store nothing"; fail=1; fi
run "real host (VM 100 and CT 900 exist)" 100 900
if [ "$RC1" = 0 ] && [ "$RC2" = 0 ] && [ "$(cat "$w/state")" = "$(printf 'firewall 100\nremote-access 900')" ]; then
  echo "ok   existing guests are moved into their pools once, and a second run changes nothing"
else echo "not ok  existing guests must be moved into their pools once"; fail=1; fi
run "only VM 100 exists" 100
if [ "$RC1" = 0 ] && [ "$RC2" = 0 ] && [ "$(cat "$w/state")" = "firewall 100" ]; then echo "ok   a missing CT 900 is skipped while VM 100 is moved"
else echo "not ok  VM 100 only"; fail=1; fi
[ "$fail" -eq 0 ]
