#!/usr/bin/env bash
# playbooks/opnsense-guard.yml (D-0063 rule 4) on this machine, with stand-ins for qm, systemctl and systemd-run that keep
# their state in files:
#   1. arm then confirm: the snapshot is taken, the timer started, then stopped and the snapshot deleted.
#   2. arm, the timer fires (its command's marker is left), then confirm: confirm fails and the snapshot stays; arm then
#      refuses; clear deletes the snapshot and the marker.
#   3. confirm with no arm fails.
#   4. clear while armed is refused; rollback rolls back and then stops the timer; clear then works.
#   5. If systemd-run fails, arm fails and deletes the snapshot it took.
#   6. If qm rollback fails, the timer stays armed and the snapshot stays; the next rollback works and then stops the timer.
# Usage: .github/hosts-check/tests/test_opnsense_guard_playbook.sh   (needs ansible-playbook)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
root=$PWD
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
mkdir -p "$t/bin"
cat > "$t/bin/qm" <<EOF
#!/bin/sh
echo "qm \$*" >> "$t/log"
case "\$1" in
  listsnapshot) [ -f "$t/snap" ] && echo '\`-> agentguard  2026-11-20 05:00:00  before'; echo '    \`-> current  You are here!' ;;
  snapshot) touch "$t/snap" ;;
  delsnapshot) rm -f "$t/snap" ;;
  rollback) if [ -f "$t/rb-fail" ]; then exit 1; fi ;;
esac
EOF
cat > "$t/bin/systemctl" <<EOF
#!/bin/sh
echo "systemctl \$*" >> "$t/log"
case "\$*" in
  "is-active "*) if [ -f "$t/timer" ]; then echo active; exit 0; else echo inactive; exit 3; fi ;;
  show*) if [ -f "$t/timer" ]; then printf 'Id=x.timer\nLoadState=loaded\nActiveState=active\nSubState=waiting\n'; else printf 'Id=x.timer\nLoadState=not-found\nActiveState=inactive\n'; fi ;;
  "stop "*) rm -f "$t/timer" ;;
esac
exit 0
EOF
cat > "$t/bin/systemd-run" <<EOF
#!/bin/sh
echo "systemd-run \$*" >> "$t/log"
[ -f "$t/sdrun-fail" ] && exit 1
touch "$t/timer"
EOF
chmod +x "$t/bin"/*
printf 'proxmox:\n  hosts:\n    h:\n      ansible_connection: local\n' > "$t/inv.yml"
g() { # action: runs the playbook, returns its exit code
  PATH="$t/bin:$PATH" ANSIBLE_PYTHON_INTERPRETER=auto_silent ansible-playbook -i "$t/inv.yml" "$root/hosts/ansible/playbooks/opnsense-guard.yml" \
    -e "opnsense_guard_action=$1" -e "opnsense_guard_marker=$t/fired" > "$t/out-$1" 2>&1
}
fire() { rm -f "$t/timer"; touch "$t/fired"; }   # what the timer's command does on the host, before its rollback

# 1
g arm && [ -f "$t/snap" ] && [ -f "$t/timer" ] && g confirm && [ ! -f "$t/snap" ] && [ ! -f "$t/timer" ] \
  && ok "1 arm then confirm: snapshot and timer, then neither" || bad "1 $(tail -3 "$t/out-confirm")"
# 2
g arm; fire
if g confirm; then bad "2 confirm passed after the timer fired"
elif [ -f "$t/snap" ] && grep -q "The timer has fired" "$t/out-confirm"; then ok "2 confirm after the timer fired fails and keeps the snapshot"
else bad "2 $(tail -3 "$t/out-confirm")"; fi
g arm && bad "2 arm passed over a left-over snapshot" || ok "2 arm refuses over a left-over snapshot"
g clear && [ ! -f "$t/snap" ] && [ ! -f "$t/fired" ] && ok "2 clear deletes the snapshot and the marker" || bad "2 clear $(tail -3 "$t/out-clear")"
# 3
g confirm && bad "3 confirm passed with no arm" || ok "3 confirm with no arm fails"
# 4
g arm
g clear && bad "4 clear passed while armed" || { [ -f "$t/snap" ] && ok "4 clear is refused while armed"; }
g rollback && [ ! -f "$t/timer" ] && grep -q "qm rollback 100 agentguard --start 1" "$t/log" && [ -f "$t/snap" ] \
  && ok "4 rollback stops the timer, rolls back and keeps the snapshot" || bad "4 rollback $(tail -3 "$t/out-rollback")"
g clear && [ ! -f "$t/snap" ] && ok "4 clear after a rollback" || bad "4 clear"
# 5
touch "$t/sdrun-fail"
g arm && bad "5 arm passed with no timer" || { [ ! -f "$t/snap" ] && ok "5 no timer: arm fails and deletes its snapshot" || bad "5 snapshot left"; }
rm -f "$t/sdrun-fail"
# 6 a rollback whose `qm rollback` fails keeps the timer armed (the automatic rollback still comes) and keeps the snapshot; a later one works
: > "$t/log"; g arm; touch "$t/rb-fail"
if g rollback; then bad "6 rollback passed though qm rollback failed"
elif [ -f "$t/timer" ] && [ -f "$t/snap" ] && ! grep -q "^systemctl stop" "$t/log" ; then ok "6 a failing rollback keeps the timer armed and the snapshot"
else bad "6 timer=$([ -f "$t/timer" ] && echo armed || echo off) snap=$([ -f "$t/snap" ] && echo yes || echo no) $(tail -3 "$t/out-rollback")"; fi
rm -f "$t/rb-fail"
g rollback && [ ! -f "$t/timer" ] && [ -f "$t/snap" ] && ok "6 the next rollback works and then stops the timer" || bad "6 retry $(tail -3 "$t/out-rollback")"
g clear
exit "$fail"
