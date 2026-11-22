#!/usr/bin/env bash
# pass-record.sh (D-0042 rule 2, rule 8): it checks every argument and writes nothing on a bad one, keys the ledger by
# repository and head, refuses a builder record for a builder-written PR, and sets and clears the halt flag.
# Runs a copy with the work and libexec folders moved into a temp folder, and a fake pr-merge.sh that prints the lane.
set -uo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)/hosts/ansible/roles/agent_box/files/pass-record.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
mkdir "$t/libexec" "$t/work"
sed "s|^work=/var/lib/agent-box|work=$t/work|; s|^libexec=/usr/local/libexec/agent-box|libexec=$t/libexec|" "$src" > "$t/pass-record.sh"
printf '#!/bin/sh\n[ "$LANE" = unreadable ] && exit 1\necho "$LANE"\n' > "$t/libexec/pr-merge.sh"; chmod +x "$t/libexec/pr-merge.sh"
H=$(printf 'a%.0s' $(seq 40)); R=cmsg_ABCDEFGHIJKL; T=2026-11-14T13:00:00Z
pr() { bash "$t/pass-record.sh" "$@" 2>&1; echo "rc=$?"; }
check() { if [[ $2 == *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi; }
none() { if [[ ! -e "$t/work/passes/central-hub/$H.jsonl" ]]; then echo "ok   $1"; else echo "FAIL $1: a line was written"; fail=1; fi; }
out=$(pr add misspelled jonhill90/central-hub 7 "$H" $R $T orchestrator); check "an unknown role exits 2" "$out" "rc=2"; none "the unknown role writes nothing"
out=$(pr add reviewer jonhill90/elsewhere 7 "$H" $R $T orchestrator); check "another repository exits 2" "$out" "rc=2"
out=$(pr add reviewer jonhill90/central-hub x7 "$H" $R $T orchestrator); check "a non-numeric PR exits 2" "$out" "rc=2"
out=$(pr add reviewer jonhill90/central-hub 7 abc $R $T orchestrator); check "a short head exits 2" "$out" "rc=2"
out=$(pr add reviewer jonhill90/central-hub 7 "$H" notamsg $T orchestrator); check "a relay ref that is not a cmsg id exits 2" "$out" "rc=2"
out=$(pr add reviewer jonhill90/central-hub 7 "$H" $R yesterday orchestrator); check "a relay time that is not ISO exits 2" "$out" "rc=2"
out=$(pr add reviewer jonhill90/central-hub 7 "$H" $R $T stranger); check "a recorder other than orchestrator, builder or reviewer exits 2" "$out" "rc=2"; none "none of the bad calls wrote anything"
out=$(pr add reviewer jonhill90/central-hub 7 "$H" $R $T); check "a missing argument exits 2" "$out" "rc=2"
out=$(LANE=plan pr add owner-tap jonhill90/central-hub 7 "$H" $R $T builder); check "owner-tap from the builder exits 2" "$out" "rc=2"; none "owner-tap from the builder writes nothing"
for role in reviewer council-a council-b council-c owner-tap; do out=$(pr add $role jonhill90/central-hub 7 "$H" $R $T orchestrator); check "$role is recorded" "$out" "rc=0"; done
f="$t/work/passes/central-hub/$H.jsonl"
[[ $(wc -l < "$f") == 5 ]] && echo "ok   five lines in the file for this head" || { echo "FAIL: line count"; fail=1; }
python3 -I -c 'import json,sys; [json.loads(l) for l in open(sys.argv[1])]; print("ok   every line is JSON")' "$f" || fail=1
[[ $(stat -c %a "$f") == 600 && $(stat -c %a "$t/work/passes") == 700 ]] && echo "ok   the ledger is 0600 in a 0700 folder" || { echo "FAIL: modes"; fail=1; }
H3=$(printf 'c%.0s' $(seq 40))
out=$(pr add reviewer jonhill90/central-hub 8 "$H3" $R $T reviewer); check "the reviewer records its own pass" "$out" "rc=0"
out=$(pr add council-a jonhill90/central-hub 8 "$H3" $R $T reviewer); check "the reviewer does not record a council line" "$out" "rc=2"
out=$(pr add owner-tap jonhill90/central-hub 8 "$H3" $R $T reviewer); check "the reviewer does not record an owner-tap" "$out" "rc=2"
[[ $(wc -l < "$t/work/passes/central-hub/$H3.jsonl") == 1 ]] && echo "ok   only the reviewer's own line was written for that head" || { echo "FAIL: reviewer lines"; fail=1; }
H2=$(printf 'b%.0s' $(seq 40)); out=$(bash "$t/pass-record.sh" show jonhill90/central-hub "$H2" 2>&1); check "another head has an empty ledger (no carry-over)" "$out" "no ledger"
out=$(LANE=builder pr add reviewer jonhill90/central-hub 8 "$H2" $R $T builder); check "a builder record for a builder-written PR exits 2" "$out" "rc=2"
out=$(LANE=unreadable pr add reviewer jonhill90/central-hub 8 "$H2" $R $T builder); check "a builder record when the lane cannot be read exits 2" "$out" "rc=2"
out=$(LANE=plan pr add reviewer jonhill90/central-hub 8 "$H2" $R $T builder); check "a builder record for another lane's PR is written" "$out" "rc=0"
out=$(LANE="Builder lane" pr add reviewer jonhill90/central-hub 8 "$H2" $R $T builder); check "a label that starts with builder in any case is the builder" "$out" "rc=2"
out=$(LANE="agent box builder" pr add reviewer jonhill90/central-hub 8 "$H2" $R $T builder); check "a label that ends with builder is the builder" "$out" "rc=2"
out=$(LANE="The Box-Builder lane" pr add reviewer jonhill90/central-hub 8 "$H2" $R $T builder); check "builder as a word inside a longer label is the builder" "$out" "rc=2"
out=$(LANE="OpenBao thread" pr add reviewer jonhill90/central-hub 8 "$H2" $R $T builder); check "a label with no builder word is not the builder" "$out" "rc=0"
out=$(LANE="bobuilders" pr add reviewer jonhill90/central-hub 8 "$H2" $R $T builder); check "builder inside another word is not the builder" "$out" "rc=0"
out=$(LANE=builder pr add reviewer jonhill90/central-hub 9 "$H2" $R $T orchestrator); check "the orchestrator may record for any PR" "$out" "rc=0"
out=$(pr halt notamsg orchestrator); check "halt needs a relay ref" "$out" "rc=2"
out=$(pr halt $R); check "halt needs a recorder" "$out" "rc=2"
out=$(pr halt $R builder); check "any lane may halt" "$out" "rc=0"; [[ -f "$t/work/passes/HALT" ]] && echo "ok   the flag file exists" || { echo "FAIL: no flag"; fail=1; }
for who in reviewer council-a council-b council-c; do out=$(pr halt $R $who); check "halt is accepted from $who" "$out" "rc=0"; done
out=$(pr halt $R stranger); check "halt from an unknown recorder exits 2" "$out" "rc=2"
out=$(pr resume $R council-a); check "resume by a council exits 2" "$out" "rc=2"
out=$(pr resume $R builder); check "resume by the builder exits 2" "$out" "rc=2"; [[ -f "$t/work/passes/HALT" ]] && echo "ok   the flag stays after a refused resume" || { echo "FAIL: flag gone"; fail=1; }
out=$(pr resume $R orchestrator); check "resume by the orchestrator clears the flag" "$out" "rc=0"; [[ ! -e "$t/work/passes/HALT" ]] && echo "ok   the flag file is gone" || { echo "FAIL: flag stays"; fail=1; }
[[ $(wc -l < "$t/work/passes/halt.log") == 6 ]] && echo "ok   halt.log has one line per accepted halt and resume" || { echo "FAIL: halt.log"; fail=1; }
sed 's|^    \[\[ \$role != owner-tap.*|    true|' "$t/pass-record.sh" > "$t/mut2.sh"
H4=$(printf 'd%.0s' $(seq 40)); out=$(LANE=plan bash "$t/mut2.sh" add owner-tap jonhill90/central-hub 8 "$H4" $R $T builder 2>&1; echo "rc=$?")
[[ $out == *"rc=0"* ]] && echo "ok   mutation: without the owner-tap rule a builder records a tap" || { echo "FAIL: the owner-tap mutation did nothing: $out"; fail=1; }
# digest-pass (the reviewer's pass of a box limit change, read by box-apply in place of an approval PR)
F1=$(printf 'd%.0s' $(seq 40)); F2=$(printf 'e%.0s' $(seq 40)); D=$(printf 'f%.0s' $(seq 64)); L="$t/work/passes/limits.jsonl"
out=$(pr digest-pass "$F1" "$F2" "$D" $R $T reviewer); check "the reviewer records a digest pass" "$out" "rc=0"
out=$(pr digest-pass "$F1" "$F2" "$D" $R $T orchestrator); check "a digest pass from any other recorder exits 2" "$out" "rc=2"
out=$(pr digest-pass abc "$F2" "$D" $R $T reviewer); check "a short from-commit exits 2" "$out" "rc=2"
out=$(pr digest-pass "$F1" "$F1" "$D" $R $T reviewer); check "from equal to to exits 2" "$out" "rc=2"
out=$(pr digest-pass "$F1" "$F2" abc $R $T reviewer); check "a short digest exits 2" "$out" "rc=2"
out=$(pr digest-pass "$F1" "$F2" "$D" notamsg $T reviewer); check "a relay ref that is not a cmsg id exits 2" "$out" "rc=2"
[[ $(wc -l < "$L") == 1 && $(stat -c %a "$L") == 600 ]] && python3 -I -c 'import json,sys; e=json.loads(open(sys.argv[1]).readline()); assert e["recorder"]=="reviewer" and e["from"]==sys.argv[2] and e["to"]==sys.argv[3]' "$L" "$F1" "$F2" \
  && echo "ok   only the reviewer's one good line was written, 0600, with from, to and recorder" || { echo "FAIL: digest-pass ledger"; fail=1; }
# Mutation: without the resume rule a builder lifts the halt.
sed 's|^    \[\[ \$1 == halt .*|    true|' "$t/pass-record.sh" > "$t/mut3.sh"; bash "$t/mut3.sh" halt $R orchestrator > /dev/null 2>&1
out=$(bash "$t/mut3.sh" resume $R builder 2>&1; echo "rc=$?"); [[ $out == *"rc=0"* ]] && echo "ok   mutation: without the resume rule a builder lifts the halt" || { echo "FAIL: resume mutation did nothing: $out"; fail=1; }
# Mutation: without the lane rule, the builder-written PR is recorded, so the check above must fail.
sed 's|\[\[ ! \${lane,,} =~ .*\]\] \|\| die|true \|\| die|' "$t/pass-record.sh" > "$t/mut.sh"
H3=$(printf 'c%.0s' $(seq 40)); out=$(LANE=builder bash "$t/mut.sh" add reviewer jonhill90/central-hub 8 "$H3" $R $T builder 2>&1; echo "rc=$?")
[[ $out == *"rc=0"* ]] && echo "ok   mutation: without the lane rule the builder's own PR is recorded" || { echo "FAIL: the mutation did not change anything: $out"; fail=1; }
exit $fail
