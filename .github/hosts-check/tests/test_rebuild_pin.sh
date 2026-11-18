#!/usr/bin/env bash
# The dev rebuild wrapper's commit argument (hosts/ansible/roles/agent_box/files/rebuild.sh):
#   1. Only up and rebuild take an argument, 7 to 40 hex digits; any other argument, or one for another action, is a
#      usage error before anything is read (diag with an argument used to fall through to a build).
#   2. checkout_main, against a real git repository: no commit checks out main's newest; a commit on main, short or
#      long, checks out that commit; a commit only on another branch, or one the checkout lacks, is refused.
#   3. A commit on main older than the floor (PIN_FLOOR) is refused, the floor itself is taken, and rebuild.sh names
#      the floor as one full commit ID.
#   4. The box's sudo line lets a session pass the commit to up and rebuild.
#   5. rebuild.sh and rebuild-prod.sh name the same floor, and (where the checkout holds its history) the floor's own
#      rebuild-k8s.sh tears dev down after every full run under ephemeral-dev (#624), so no pin leaves dev up.
# Usage: .github/hosts-check/tests/test_rebuild_pin.sh   (needs git)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
src=$root/hosts/ansible/roles/agent_box/files/rebuild.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

# 1
r1=""
for args in "up nothex" "up 0123" "up 0123abc extra" "rebuild main" "teardown 0123abc" "identity 0123abc" "diag extra" "log extra" "apply"; do
  # shellcheck disable=SC2086
  bash "$src" $args > "$t/out" 2>&1; r1+="$?:$(grep -c '^usage: rebuild up|rebuild \[<commit>\]' "$t/out") "
done
bash "$src" up 0123abc > "$t/out" 2>&1; r1b=$?; o1b=$(cat "$t/out")
if [[ $r1 == "2:1 2:1 2:1 2:1 2:1 2:1 2:1 2:1 2:1 " && $r1b -ne 2 && $o1b != *usage* ]]; then
  ok "1. only up and rebuild take a commit, 7 to 40 hex digits; anything else is a usage error before anything is read"
else bad "1. [$r1] $r1b $o1b"; fi

# 2
sed -n '/^checkout_main() {/,/^}/p' "$src" > "$t/fn.sh"
grep -q 'merge-base --is-ancestor' "$t/fn.sh" || { echo "FAIL: checkout_main was not found in rebuild.sh"; exit 1; }
g() { git -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main "$@"; }
g init -q --bare "$t/origin.git"
g clone -q "$t/origin.git" "$t/work" 2>/dev/null
(cd "$t/work" && g commit -q --allow-empty -m old && g push -q origin HEAD:main &&
 g commit -q --allow-empty -m one && g push -q origin HEAD:main &&
 g commit -q --allow-empty -m two && g push -q origin HEAD:main &&
 g checkout -q -b side && g commit -q --allow-empty -m side && g push -q origin side)
old=$(git -C "$t/work" rev-parse main~2) one=$(git -C "$t/work" rev-parse main~1) two=$(git -C "$t/work" rev-parse main) side=$(git -C "$t/work" rev-parse side)
g clone -q --no-checkout "$t/origin.git" "$t/box"
git -C "$t/box" fetch -q origin side   # the side commit is in the checkout's objects, but not on main
co() { PIN_FLOOR=$one bash -c '. "$1"; checkout_main "$2" "$3"' _ "$t/fn.sh" "$t/box" "${1:-}" > "$t/out" 2>&1; rc=$?; head=$(git -C "$t/box" rev-parse HEAD 2>/dev/null); out=$(cat "$t/out"); }
co; r2a="$rc $([[ $head == "$two" ]] && echo newest)"
co "${one:0:7}"; r2b="$rc $([[ $head == "$one" ]] && echo pinned)"
co "$one"; r2c="$rc $([[ $head == "$one" ]] && echo pinned)"
co "$side"; r2d="$rc $([[ $head == "$one" ]] && echo unmoved) $([[ $out == *"commit $side is not on main"* ]] && echo said)"
co deadbee; r2e="$rc $([[ $out == *"commit deadbee is not in the box's checkout of main"* ]] && echo said)"
if [[ $r2a == "0 newest" && $r2b == "0 pinned" && $r2c == "0 pinned" && $r2d == "1 unmoved said" && $r2e == "1 said" ]]; then
  ok "2. no commit: main's newest; a commit on main, short or long: that commit; a commit off main or unknown: refused"
else bad "2. [$r2a] [$r2b] [$r2c] [$r2d] [$r2e]"; fi

# 3
co "$two"; co "$old"; r4a="$rc $([[ $head == "$two" ]] && echo unmoved) $([[ $out == *"commit $old is older than the floor ${one:0:7}"* ]] && echo said)"
co "${one:0:7}"; r4b="$rc $([[ $head == "$one" ]] && echo pinned)"
grep -qE '^PIN_FLOOR=[0-9a-f]{40}$' "$src"; r4c=$?
if [[ $r4a == "1 unmoved said" && $r4b == "0 pinned" && $r4c -eq 0 ]]; then
  ok "3. a commit on main older than the floor is refused, the floor itself is taken, and the floor is a full commit ID"
else bad "3. [$r4a] [$r4b] $r4c"; fi

# 4
if grep -qF 'args: [up, "up *", rebuild, "rebuild *", teardown, identity, log, diag]' "$root/hosts/ansible/roles/agent_box/defaults/main.yml"; then
  ok "4. the sudo line lets a session pass the commit to up and rebuild, and nothing to the other actions"
else bad "4. the rebuild wrapper's sudo args do not pass a commit to up and rebuild"; fi

# 5
prod=$root/hosts/ansible/roles/agent_box/files/rebuild-prod.sh
f_dev=$(sed -n 's/^PIN_FLOOR=\([0-9a-f]\{40\}\)$/\1/p' "$src") f_prod=$(sed -n 's/^PIN_FLOOR=\([0-9a-f]\{40\}\)$/\1/p' "$prod")
r5=same
[[ -n $f_dev && $f_dev == "$f_prod" ]] || r5="dev [$f_dev] prod [$f_prod]"
if git -C "$root" cat-file -e "$f_dev^{commit}" 2>/dev/null; then
  git -C "$root" show "$f_dev:hosts/rebuild-k8s.sh" | grep -q 'dev lasts one run and is torn down now' ||
    r5+=", the floor's rebuild-k8s.sh lacks the every-run teardown"
else
  echo "note 5. the floor ${f_dev:0:7} is not in this checkout's history (a shallow clone), so its rebuild-k8s.sh is not read"
fi
if [[ $r5 == same ]]; then
  ok "5. both wrappers name the same floor, and the floor's rebuild-k8s.sh tears dev down after every full run"
else bad "5. $r5"; fi

exit $fail
