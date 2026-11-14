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
  *"test -e"*) exit "${FAKE_HALT:-1}" ;;
  *"pass-record show"*) [[ -n ${FAKE_SHOW_FAIL:-} ]] && exit 1; echo '{"role":"reviewer","relay_time":"2026-11-14T19:42:00Z"}'; exit 0 ;;
  *) echo "$FAKE_VERDICT"; exit "${FAKE_RC:-0}" ;;
esac
F
cat > "$t/bin/gh" <<'F'
#!/bin/bash
echo "gh $*" >> "$FAKE_CALLS"
F
chmod +x "$t/bin/zsh" "$t/bin/gh"
git init -q --bare "$t/origin.git"
git clone -q "$t/origin.git" "$t/co" 2>/dev/null
mkdir -p "$t/co/hosts/wrappers/mac"; cp "$src" "$t/co/hosts/wrappers/mac/merge-checked.sh"
git -C "$t/co" add -A && git -C "$t/co" -c user.name=t -c user.email=t@t commit -q -m x \
  && git -C "$t/co" push -q origin HEAD:main 2>/dev/null
git -C "$t/co" fetch -q origin main
w="$t/co/hosts/wrappers/mac/merge-checked.sh"
run() { : > "$t/calls"; PATH="$t/bin:$PATH" HOME="$t/home" FAKE_CALLS="$t/calls" bash "${W:-$w}" "$@" 2>&1; echo "rc=$?"; }
G="pr-merge: jonhill90/central-hub#7 aaaaaaa: GREEN"
R=jonhill90/central-hub
out=$(FAKE_VERDICT=$G run $R 7 $H); check "GREEN merges" "$out" "rc=0"
check "the merge is squash, pinned to the head" "$(cat "$t/calls")" "gh pr merge 7 --repo $R --squash --match-head-commit $H"
nocheck "no --admin" "$(cat "$t/calls")" "--admin"; nocheck "no --auto" "$(cat "$t/calls")" "--auto"
out=$(FAKE_VERDICT="pr-merge: x: NOT GREEN: a check failed" FAKE_RC=1 run $R 7 $H); check "NOT GREEN is refused" "$out" "rc=1"; [[ ! -s $t/calls ]] && echo "ok   NOT GREEN made no gh call" || { echo "FAIL: gh was called"; fail=1; }
out=$(FAKE_VERDICT="pr-merge: x: OWNER: rule 11" FAKE_RC=3 run $R 7 $H); check "an OWNER verdict is refused" "$out" "rc=1"; [[ ! -s $t/calls ]] && echo "ok   OWNER made no gh call" || { echo "FAIL: gh was called"; fail=1; }
out=$(FAKE_VERDICT=$G FAKE_RC=1 run $R 7 $H); check "a failed box call is refused even with GREEN text" "$out" "rc=1"
out=$(FAKE_VERDICT=$G FAKE_HALT=0 run $R 7 $H); check "a set halt flag refuses even a GREEN PR" "$out" "halt flag is set"; [[ ! -s $t/calls ]] && echo "ok   halted made no gh call" || { echo "FAIL: gh was called while halted"; fail=1; }
out=$(FAKE_VERDICT=$G FAKE_HALT=255 run $R 7 $H); check "an unreadable halt flag refuses" "$out" "could not read the box's halt flag"
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
out=$(FAKE_VERDICT=$G run $R 7 $H); check "a checkout that is not origin/main is refused" "$out" "not at origin/main"
git -C "$t/co" reset -q --hard origin/main
# Mutation: without the GREEN test a NOT GREEN verdict merges.
sed 's|^\[\[ \$rc -eq 0 && .*|true|' "$src" > "$t/co/hosts/wrappers/mac/mut.sh"
out=$(W="$t/co/hosts/wrappers/mac/mut.sh" FAKE_VERDICT="pr-merge: x: NOT GREEN: a check failed" FAKE_RC=1 run $R 7 $H)
[[ -s $t/calls ]] && echo "ok   mutation: without the GREEN test a refused PR merges" || { echo "FAIL: the mutation did nothing: $out"; fail=1; }
# Mutation: without the halt check a GREEN PR merges while the flag is set.
sed 's|^halted && die "the halt flag is set on the box.*|true|; s|^halted && die "the halt flag was set.*|true|' "$src" > "$t/co/hosts/wrappers/mac/mut2.sh"
out=$(W="$t/co/hosts/wrappers/mac/mut2.sh" FAKE_VERDICT=$G FAKE_HALT=0 run $R 7 $H)
[[ -s $t/calls ]] && echo "ok   mutation: without the halt check a halted box still merges" || { echo "FAIL: the halt mutation did nothing: $out"; fail=1; }
exit $fail
