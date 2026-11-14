#!/usr/bin/env bash
# The hourly off-box send of the dev secrets store's snapshot (hosts/ansible/roles/agent_box/files/secrets-store-offbox.sh,
# pick 237), against local restic repositories, the real restic, and stand-ins for curl, the secrets-store wrapper and
# the escrow script:
#   1. No store VM in the wrapper's state (no state file, or no VM in it): "skipped: no store", exit 0, nothing made.
#   2. A store VM whose sys/health is not 200 (sealed, or no answer) fails, before any snapshot or send.
#   3. A normal hourly run makes its own repository, sends, reads back, and forgets without pruning.
#   4. The first run from the prune hour prunes, once a day; the next run that day does not.
#   5. A failed escrow stops it before restic.
#   6. A repository restic can't open for another reason than "does not exist" fails and is never made again.
#   7. The OPNsense repository is never touched, and the job refuses to be pointed at it, inside it, or above it.
#   8. Retention works although every snapshot has its own file name: six snapshots on six hours, keep-hourly 2,
#      leaves two.
#   9. A corrupted read-back fails the run.
#  10. No password shows in the output.
# restic comes from its GitHub release, checked against the SHA-256 the role installs.
# Usage: .github/hosts-check/tests/test_secrets_store_offbox.sh   (needs curl, python3 with PyYAML, bunzip2)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
role=$root/hosts/ansible/roles/agent_box
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
def() { python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))[sys.argv[2]])' "$role/defaults/main.yml" "$1"; }

mkdir -p "$t/bin" "$t/work/state" "$t/keys/opnsense-offbox" "$t/keys/dev/openbao-snapshots"
rv=$(def agent_box_restic_version)
curl -sSLf --retry 5 --retry-delay 10 -o "$t/restic.bz2" "https://github.com/restic/restic/releases/download/v$rv/restic_${rv}_linux_amd64.bz2"
echo "$(def agent_box_restic_sha256)  $t/restic.bz2" | sha256sum -c --quiet
bunzip2 -c "$t/restic.bz2" > "$t/bin/restic-real"
# restic, logging its arguments, with a switch that corrupts what `dump` gives back.
cat > "$t/bin/restic" <<EOF
#!/bin/bash
echo "\$*" >> $t/restic-args
if [[ " \$* " == *" dump "* && -e $t/corrupt ]]; then "$t/bin/restic-real" "\$@"; printf x; else exec "$t/bin/restic-real" "\$@"; fi
EOF
# curl: sys/health answers what $t/health holds (000 is no answer).
cat > "$t/bin/curl" <<EOF
#!/bin/bash
code=\$(cat $t/health); printf '%s' "\$code"; [[ \$code != 000 ]]
EOF
# The wrapper: `snapshot` writes a new raft-*.snap with fresh bytes, as the real one does.
cat > "$t/wrapper" <<EOF
#!/bin/bash
[ "\$1" = snapshot ] || exit 9
echo called >> $t/wrapper-calls
n=\$(( \$(ls $t/keys/dev/openbao-snapshots | wc -l) + 1 ))
f=$t/keys/dev/openbao-snapshots/raft-20261114T\$(printf %02d \$n)0000Z.snap
head -c 4096 /dev/urandom > "\$f"
echo "secrets-store: snapshot \$(basename "\$f"), 4096 bytes"
EOF
echo 0 > "$t/escrow-rc"
cat > "$t/escrow" <<EOF
#!/bin/bash
[ "\$1" = ensure ] || exit 9
exit "\$(cat $t/escrow-rc)"
EOF
chmod +x "$t/bin/"* "$t/wrapper" "$t/escrow"
head -c 32 /dev/urandom | base64 > "$t/keys/opnsense-offbox/restic.txt"
cat > "$t/keys/opnsense-offbox/settings.env" <<EOF
RESTIC_REPOSITORY=$t/repo-opnsense
RESTIC_PASSWORD_FILE=$t/keys/opnsense-offbox/restic.txt
EOF
echo '{"address": "store.invalid"}' > "$t/work/secrets-store.json"
: > "$t/ca.crt"
own() { # repository, keep hourly
  cat > "$t/work/secrets-store-offbox.env" <<EOF
SNAPSHOT_REPOSITORY=${1:-$t/repo-store}
SNAPSHOT_KEEP_HOURLY=${2:-48}
SNAPSHOT_KEEP_DAILY=${3:-14}
SNAPSHOT_KEEP_MONTHLY=${3:-6}
SNAPSHOT_PRUNE_AFTER_HOUR=3
EOF
}
own
vm_state() { echo '{"resources": [{"mode": "managed", "type": "proxmox_virtual_environment_vm", "name": "store", "instances": [{}]}]}' > "$t/work/state/secrets-store.tfstate"; }
sed -e "s|^work=.*|work=$t/work|" -e "s|^settings=.*|settings=$t/keys/opnsense-offbox/settings.env|" \
    -e "s|^cacert=.*|cacert=$t/ca.crt|" -e "s|^snapshots=.*|snapshots=$t/keys/dev/openbao-snapshots|" \
    -e "s|^wrapper=.*|wrapper=$t/wrapper|" -e "s|^restic=.*|restic=$t/bin/restic|" -e "s|^escrow=.*|escrow=$t/escrow|" \
    -e "s|^now=.*|now=\$(cat $t/now)|" -e "s|PATH=/usr/local/bin|PATH=$t/bin:/usr/local/bin|" \
    "$role/files/secrets-store-offbox.sh" > "$t/send.sh"
grep -q "^escrow=$t/escrow" "$t/send.sh" && grep -q "^now=\$(cat $t/now)" "$t/send.sh" && grep -q "PATH=$t/bin:" "$t/send.sh" ||
  { echo "FAIL: the test could not point the script at its folders"; exit 1; }

fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
all=""
send() { : > "$t/restic-args"; bash "$t/send.sh" > "$t/out" 2>&1 && rc=0 || rc=$?; out=$(cat "$t/out"); all+=$out; }
count() { RESTIC_REPOSITORY=$1 RESTIC_PASSWORD_FILE=$t/keys/opnsense-offbox/restic.txt "$t/bin/restic-real" snapshots --json --tag "$2" 2>/dev/null |
  python3 -c 'import json,sys; print(len(json.load(sys.stdin) or []))'; }
called() { [[ -s $t/wrapper-calls ]]; }

# The OPNsense repository, with one copy of its own.
RESTIC_REPOSITORY=$t/repo-opnsense RESTIC_PASSWORD_FILE=$t/keys/opnsense-offbox/restic.txt "$t/bin/restic-real" init --quiet >/dev/null
echo config > "$t/config.xml"
RESTIC_REPOSITORY=$t/repo-opnsense RESTIC_PASSWORD_FILE=$t/keys/opnsense-offbox/restic.txt "$t/bin/restic-real" backup --quiet --host agent-box --tag opnsense "$t/config.xml" >/dev/null
echo 2026-11-14-01 > "$t/now"

# 1
echo 200 > "$t/health"
send
r1=$rc o1=$out
echo '{"resources": []}' > "$t/work/state/secrets-store.tfstate"
send
if [[ $r1 -eq 0 && $o1 == *"skipped: no store"* && $rc -eq 0 && $out == *"skipped: no store"* && ! -e $t/repo-store ]] && ! called; then
  ok "1. no store VM in the state: skipped, exit 0, nothing made"
else bad "1. rc=$r1/$rc $o1 / $out"; fi

# 2
vm_state
echo 503 > "$t/health"; send; r2=$rc o2=$out
echo 000 > "$t/health"; send
if [[ $r2 -ne 0 && $o2 == *"answered 503"* && $rc -ne 0 && $out == *"answered nothing"* && ! -e $t/repo-store ]] && ! called; then
  ok "2. a store VM that is sealed or does not answer fails, before any snapshot or send"
else bad "2. rc=$r2/$rc $o2 / $out"; fi
echo 200 > "$t/health"

# 3
send
if [[ $rc -eq 0 && $out == *"made the repository"* && $out == *"sent raft-"* && $(count "$t/repo-store" openbao-dev) == 1 ]] &&
   grep -q ' forget ' "$t/restic-args" && ! grep -q -- '--prune' "$t/restic-args" && [[ ! -e $t/work/state/secrets-store-offbox.pruned ]]; then
  ok "3. an hourly run makes its own repository, sends, reads back, and forgets without pruning"
else bad "3. rc=$rc $out $(cat "$t/restic-args")"; fi

# 4
echo 2026-11-14-04 > "$t/now"; send; r4=$rc o4=$out p4=$(grep -c -- 'forget.*--prune' "$t/restic-args" || true)
echo 2026-11-14-05 > "$t/now"; send; p5=$(grep -c -- '--prune' "$t/restic-args" || true)
if [[ $r4 -eq 0 && $o4 == *"pruned the repository"* && $p4 == 1 && $(cat "$t/work/state/secrets-store-offbox.pruned") == 2026-11-14 && $rc -eq 0 && $p5 == 0 ]]; then
  ok "4. the first run from the prune hour prunes, and the next one that day does not"
else bad "4. rc=$r4/$rc p4=$p4 p5=$p5 $o4"; fi

# 5
before=$(count "$t/repo-store" openbao-dev)
echo 1 > "$t/escrow-rc"; send
[[ $rc -ne 0 && $out == *"nothing sent"* && $(count "$t/repo-store" openbao-dev) == "$before" ]] \
  && ok "5. a failed escrow stops it before restic" || bad "5. rc=$rc $out"
echo 0 > "$t/escrow-rc"

# 6
head -c 32 /dev/urandom | base64 > "$t/other-password"
RESTIC_REPOSITORY=$t/repo-other RESTIC_PASSWORD_FILE=$t/other-password "$t/bin/restic-real" init --quiet >/dev/null
own "$t/repo-other"; send
if [[ $rc -ne 0 && $out == *"could not open the repository"* && $out == *"not made"* ]] && ! grep -q '^init' "$t/restic-args"; then
  ok "6. a repository restic can't open (wrong password) fails, and no init is tried"
else bad "6. rc=$rc $out $(cat "$t/restic-args")"; fi
own "$t/repo-opnsense"; send
r7=$rc o7=$out
own "$t/repo-opnsense/openbao-dev"; send
r7b=$rc o7b=$out
own "$t"; send
r7c=$rc o7c=$out
own

# 7
if [[ $r7 -ne 0 && $o7 == *"must not be the OPNsense repository"* && $(count "$t/repo-opnsense" opnsense) == 1 && $(count "$t/repo-opnsense" openbao-dev) == 0 ]]; then
  ok "7. the OPNsense repository keeps its one copy, and the job refuses to be pointed at it"
else bad "7. rc=$r7 $o7"; fi
if [[ $r7b -ne 0 && $o7b == *"nor inside it"* && $r7c -ne 0 && $o7c == *"nor hold it"* && ! -e $t/repo-opnsense/openbao-dev ]]; then
  ok "7b. a path inside the OPNsense repository, or one that holds it, is refused too"
else bad "7b. rc=$r7b/$r7c $o7b / $o7c"; fi

# 8
for h in 10 11 12 13 14; do
  f=$t/keys/dev/openbao-snapshots/raft-20261113T${h}0000Z.snap
  head -c 4096 /dev/urandom > "$f"
  RESTIC_REPOSITORY=$t/repo-store RESTIC_PASSWORD_FILE=$t/keys/opnsense-offbox/restic.txt "$t/bin/restic-real" \
    backup --quiet --host agent-box --tag openbao-dev --time "2026-11-13 $h:00:00" "$f" >/dev/null
done
before=$(count "$t/repo-store" openbao-dev)
own "$t/repo-store" 2 0
send
[[ $rc -eq 0 && $before -ge 6 && $(count "$t/repo-store" openbao-dev) == 2 ]] \
  && ok "8. retention: $before snapshots, keep-hourly 2, leaves 2" || bad "8. rc=$rc before=$before after=$(count "$t/repo-store" openbao-dev) $out"
own

# 9
touch "$t/corrupt"; send
[[ $rc -ne 0 && $out == *"differs from"* ]] && ok "9. a corrupted read-back fails the run" || bad "9. rc=$rc $out"
rm -f "$t/corrupt"

# 10
if [[ $all == *"$(cat "$t/keys/opnsense-offbox/restic.txt")"* ]]; then bad "10. the password shows in the output"
else ok "10. no password in the output"; fi
exit "$fail"
