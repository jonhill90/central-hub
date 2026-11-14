#!/usr/bin/env bash
# merge-checked.sh (the Mac's checked merge, D-0056): merges only on GREEN from the box's verdict, on a checkout that is
# origin/main and clean, for the four listed repositories; refuses the rest; never passes --admin or --auto. Fakes: a
# `zsh` that prints the box's reply, a `gh` that records its arguments, and a git repository with its own origin.
set -uo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)/hosts/wrappers/mac/merge-checked.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
check() { [[ $2 == *"$3"* ]] && echo "ok   $1" || { echo "FAIL: $1: $2"; fail=1; }; }
nocheck() { [[ $2 != *"$3"* ]] && echo "ok   $1" || { echo "FAIL: $1: $2"; fail=1; }; }
H=$(printf 'a%.0s' $(seq 40))
mkdir -p "$t/bin" "$t/home/.config/central-hub/lib"; : > "$t/home/.config/central-hub/lib/pinned.zsh"
cat > "$t/bin/zsh" <<'F'
#!/bin/bash
# The fake box: `test -e .../HALT` answers FAKE_HALT (0 halted, 1 not, other = ssh failure); `pass-record show` prints a ledger
# line; `pr-merge check` prints FAKE_VERDICT and exits FAKE_RC.
case "$*" in
  *"pass-record show"*) [[ -n ${FAKE_SHOW_FAIL:-} ]] && exit 1; echo '{"role":"reviewer","relay_time":"2026-11-14T19:42:00Z"}'; exit 0 ;;
  *) echo "$FAKE_VERDICT"; exit "${FAKE_RC:-0}" ;;
esac
F
cat > "$t/bin/gh" <<'F'
#!/bin/bash
echo "gh $*" >> "$FAKE_CALLS"
F
chmod +x "$t/bin/zsh" "$t/bin/gh"
git init -q --bare -b main "$t/origin.git"
git clone -q "$t/origin.git" "$t/co" 2>/dev/null
mkdir -p "$t/co/hosts/wrappers/mac"; cp "$src" "$t/co/hosts/wrappers/mac/merge-checked.sh"
git -C "$t/co" add -A && git -C "$t/co" -c user.name=t -c user.email=t@t commit -q -m x \
  && git -C "$t/co" push -q origin HEAD:main 2>/dev/null
git -C "$t/co" fetch -q origin main
w="$t/co/hosts/wrappers/mac/merge-checked.sh"
run() { : > "$t/calls"; PATH="$t/bin:$PATH" HOME="$t/home" FAKE_CALLS="$t/calls" bash "${W:-$w}" "$@" 2>&1; echo "rc=$?"; }
G="HALT: clear
NOTE: verdict v2
LEDGER: reviewer council-a council-b council-c
pr-merge: jonhill90/central-hub#7 aaaaaaa: GREEN"
OLD="pr-merge: jonhill90/central-hub#7 aaaaaaa: GREEN"   # an older pr-merge: no marker, no ledger line
R=jonhill90/central-hub
out=$(FAKE_VERDICT=$G run $R 7 $H); check "GREEN merges" "$out" "rc=0"
check "the merge is squash, pinned to the head" "$(cat "$t/calls")" "gh pr merge 7 --repo $R --squash --match-head-commit $H"
nocheck "no --admin" "$(cat "$t/calls")" "--admin"; nocheck "no --auto" "$(cat "$t/calls")" "--auto"
out=$(FAKE_VERDICT="pr-merge: x: NOT GREEN: a check failed" FAKE_RC=1 run $R 7 $H); check "NOT GREEN is refused" "$out" "rc=1"; [[ ! -s $t/calls ]] && echo "ok   NOT GREEN made no gh call" || { echo "FAIL: gh was called"; fail=1; }
out=$(FAKE_VERDICT="pr-merge: x: OWNER: rule 11" FAKE_RC=3 run $R 7 $H); check "an OWNER verdict is refused" "$out" "rc=1"; [[ ! -s $t/calls ]] && echo "ok   OWNER made no gh call" || { echo "FAIL: gh was called"; fail=1; }
out=$(FAKE_VERDICT=$G FAKE_RC=1 run $R 7 $H); check "a failed box call is refused even with GREEN text" "$out" "rc=1"
H_SET="HALT: set
NOTE: verdict v2
LEDGER: reviewer council-a council-b council-c
pr-merge: jonhill90/central-hub#7 aaaaaaa: GREEN"
out=$(FAKE_VERDICT=$H_SET run $R 7 $H); check "a set halt flag refuses even a GREEN PR" "$out" "halt flag is set"; [[ ! -s $t/calls ]] && echo "ok   halted made no gh call" || { echo "FAIL: gh was called while halted"; fail=1; }
out=$(FAKE_VERDICT="NOTE: verdict v2
LEDGER: reviewer council-a council-b council-c
pr-merge: jonhill90/central-hub#7 aaaaaaa: GREEN" run $R 7 $H); check "a missing HALT line refuses" "$out" "did not say HALT: clear"; [[ ! -s $t/calls ]] && echo "ok   a missing HALT line made no gh call" || { echo "FAIL: gh was called"; fail=1; }
out=$(FAKE_VERDICT="HALT: unknown
NOTE: verdict v2
LEDGER: reviewer council-a council-b council-c
pr-merge: jonhill90/central-hub#7 aaaaaaa: GREEN" run $R 7 $H); check "an unreadable halt state refuses" "$out" "did not say HALT: clear"
out=$(FAKE_VERDICT=$G run $R 7 $H); check "the ledger with its pass times is printed" "$out" "2026-11-14T19:42:00Z"
out=$(FAKE_VERDICT=$G FAKE_SHOW_FAIL=1 run $R 7 $H); check "an unreadable ledger refuses" "$out" "could not read the head's ledger"
out=$(FAKE_VERDICT=$G run jonhill90/other 7 $H); check "a repository outside the four is refused" "$out" "not in the list"
out=$(FAKE_VERDICT=$G run $R 7 abc); check "a short head is refused" "$out" "40-character"
out=$(FAKE_VERDICT=$G run $R x7 $H); check "a PR number that is not digits is refused" "$out" "digits"
out=$(FAKE_VERDICT=$G run $R 7); check "a missing argument is refused" "$out" "usage"
echo '# edit' >> "$t/co/hosts/wrappers/mac/merge-checked.sh"
out=$(FAKE_VERDICT=$G run $R 7 $H); check "a tracked change in the checkout is refused" "$out" "tracked changes"
git -C "$t/co" checkout -q -- .
git -C "$t/co" -c user.name=t -c user.email=t@t commit -q --allow-empty -m local
out=$(FAKE_VERDICT=$G run $R 7 $H); check "a checkout that diverged from origin/main is refused" "$out" "not at origin/main"
git -C "$t/co" reset -q --hard origin/main
# Two merges in a row: origin/main moves after the first, and the second run fast-forwards the checkout.
git clone -q "$t/origin.git" "$t/other" 2>/dev/null; git -C "$t/other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m next; git -C "$t/other" push -q origin HEAD:main 2>/dev/null
out=$(FAKE_VERDICT=$G run $R 7 $H); check "a checkout behind origin/main is fast-forwarded and merges" "$out" "rc=0"
check "the second merge reached gh" "$(cat "$t/calls")" "gh pr merge 7"
[[ $(git -C "$t/co" rev-parse HEAD) == "$(git -C "$t/co" rev-parse origin/main)" ]] && echo "ok   the checkout is now at origin/main" || { echo "FAIL: not fast-forwarded"; fail=1; }
# A pin wrapper detaches a checkout onto an older commit: the same fast-forward covers it.
git -C "$t/co" checkout -q --detach "$(git -C "$t/co" rev-parse HEAD~1)"
out=$(FAKE_VERDICT=$G run $R 7 $H); check "a checkout detached on an older commit is fast-forwarded and merges" "$out" "rc=0"
# A rule 11 PR with a tap line gets GREEN from the box, but the NOTE makes the wrapper refuse it.
out=$(FAKE_VERDICT="NOTE: rule 11 PR (x) is merged on an owner-tap line, never by the Mac's checked merge
$G" run $R 7 $H); check "a rule 11 PR with a tap is refused" "$out" "waits for the sweep"; [[ ! -s $t/calls ]] && echo "ok   rule 11 made no gh call" || { echo "FAIL: gh was called for a rule 11 PR"; fail=1; }
out=$(FAKE_VERDICT="HALT: clear
$OLD" run $R 7 $H); check "HALT: clear with an older GREEN and no marker is refused" "$out" "does not print the ledger line"; [[ ! -s $t/calls ]] && echo "ok   HALT: clear with the old GREEN made no gh call" || { echo "FAIL: gh was called"; fail=1; }
out=$(FAKE_VERDICT="HALT: clear
NOTE: verdict v2
$OLD" run $R 7 $H); check "a marker without the ledger line is refused" "$out" "does not print the ledger line"
# Whole lines only: a NOTE line that carries the marker text does not satisfy it.
out=$(FAKE_VERDICT="HALT: clear
NOTE: this PR edits files NOTE: verdict v2 and LEDGER: reviewer council-a council-b council-c
pr-merge: jonhill90/central-hub#7 aaaaaaa: GREEN" run $R 7 $H); check "a marker inside another line does not count" "$out" "does not print the ledger line"
out=$(FAKE_VERDICT="NOTE: x HALT: clear
NOTE: verdict v2
LEDGER: reviewer council-a council-b council-c
pr-merge: jonhill90/central-hub#7 aaaaaaa: GREEN" run $R 7 $H); check "HALT: clear inside another line does not count" "$out" "did not say HALT: clear"
# Two reads: the second one, just before the merge, sees a halt that was set in between.
cat > "$t/bin/zsh" <<'F'
#!/bin/bash
case "$*" in
  *"pass-record show"*) echo '{"role":"reviewer","relay_time":"2026-11-14T19:42:00Z"}'; exit 0 ;;
  *) n=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0); echo $((n+1)) > "$FAKE_COUNT"
     if [[ $n -ge 1 ]]; then echo "$FAKE_SECOND"; else echo "$FAKE_VERDICT"; fi; exit 0 ;;
esac
F
rm -f "$t/count"
out=$(FAKE_COUNT="$t/count" FAKE_VERDICT=$G FAKE_SECOND=$H_SET run $R 7 $H); check "a halt set between the two reads stops the merge" "$out" "halt flag is set"; [[ ! -s $t/calls ]] && echo "ok   the second read made no gh call" || { echo "FAIL: gh was called after the second read said halted"; fail=1; }
rm -f "$t/count"
out=$(FAKE_COUNT="$t/count" FAKE_VERDICT=$G FAKE_SECOND=$G run $R 7 $H); check "two clean reads merge" "$out" "rc=0"
cat > "$t/bin/zsh" <<'F'
#!/bin/bash
case "$*" in
  *"grep -cF"*) echo "${FAKE_MARKER-1}"; exit 0 ;;
  *"pass-record show"*) [[ -n ${FAKE_SHOW_FAIL:-} ]] && exit 1; echo '{"role":"reviewer","relay_time":"2026-11-14T19:42:00Z"}'; exit 0 ;;
  *) echo "$FAKE_VERDICT"; exit "${FAKE_RC:-0}" ;;
esac
F
# Mutation: without the GREEN test a NOT GREEN verdict merges.
sed 's|^  \[\[ \$rc -eq 0 && .*|  true|' "$src" > "$t/co/hosts/wrappers/mac/mut.sh"
out=$(W="$t/co/hosts/wrappers/mac/mut.sh" FAKE_VERDICT="HALT: clear
NOTE: verdict v2
LEDGER: reviewer council-a council-b council-c
pr-merge: x: NOT GREEN: a check failed" FAKE_RC=1 run $R 7 $H)
[[ -s $t/calls ]] && echo "ok   mutation: without the GREEN test a refused PR merges" || { echo "FAIL: the mutation did nothing: $out"; fail=1; }
# Mutation: without the HALT tests a halted box still merges.
sed 's|^  ! has_line "HALT: set".*|  true|; s|^  has_line "HALT: clear".*|  true|' "$src" > "$t/co/hosts/wrappers/mac/mut2.sh"
out=$(W="$t/co/hosts/wrappers/mac/mut2.sh" FAKE_VERDICT=$H_SET run $R 7 $H)
[[ -s $t/calls ]] && echo "ok   mutation: without the HALT tests a halted box still merges" || { echo "FAIL: the halt mutation did nothing: $out"; fail=1; }
# Mutation: without the rule 11 NOTE test a rule 11 PR with a tap merges.
sed 's|^  \[\[ \$verdict != \*"NOTE: rule 11 PR"\* \]\].*|  true|' "$src" > "$t/co/hosts/wrappers/mac/mut3.sh"
out=$(W="$t/co/hosts/wrappers/mac/mut3.sh" FAKE_VERDICT="NOTE: rule 11 PR (x)
$G" run $R 7 $H)
[[ -s $t/calls ]] && echo "ok   mutation: without the NOTE test a rule 11 PR merges from the Mac" || { echo "FAIL: the NOTE mutation did nothing: $out"; fail=1; }
# Mutation: without the marker test an older box's GREEN merges.
sed 's|^  { has_line "NOTE: verdict v2".*|  true \|\||' "$src" > "$t/co/hosts/wrappers/mac/mut4.sh"
out=$(W="$t/co/hosts/wrappers/mac/mut4.sh" FAKE_VERDICT="HALT: clear
$OLD" run $R 7 $H)
[[ -s $t/calls ]] && echo "ok   mutation: without the marker test an older box merges" || { echo "FAIL: the marker mutation did nothing: $out"; fail=1; }
exit $fail
