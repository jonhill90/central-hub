#!/usr/bin/env bash
# Merge one pull request from the Mac only when the box's verdict is GREEN on that exact head (D-0042 rules 2 and 11, D-0056).
#   merge-checked.sh OWNER/REPO PR_NUMBER HEAD_SHA
# It never decides anything itself: the verdict, the ledger and the rule 11 file list live on the box (`pr-merge check`).
# A PR that is not GREEN, or that needs the owner's tap (rule 11), is refused here and waits for the box's sweep; the
# raw `gh pr merge` is never the fallback. Merges squash, pinned to HEAD_SHA; never --admin, never --auto.
# The Mac's allow line names this file inside the main checkout, so the file that runs is the file on main.
# Private values (the box address and its ssh options) stay in the Mac's own lib, outside this repository.
set -euo pipefail

die() { echo "merge-checked: $*" >&2; exit "${2:-2}"; }
[[ $# -eq 3 ]] || die "usage: merge-checked.sh OWNER/REPO PR_NUMBER HEAD_SHA"
repo=$1 pr=$2 head=$3
case $repo in
  jonhill90/central-hub | jonhill90/inpara | jonhill90/agent-notebook | jonhill90/obsidian-graph-3d) ;;
  *) die "repository not in the list: $repo" ;;
esac
[[ $pr =~ ^[0-9]{1,7}$ ]] || die "PR number must be digits: $pr"
[[ $head =~ ^[0-9a-f]{40}$ ]] || die "head must be a full 40-character commit id"

# This file must be the one on main: its own checkout (one no pin wrapper touches) equals origin/main, and no tracked file differs.
# A checkout that is behind origin/main (each merge moves it) is fast-forwarded once and the wrapper starts again from the new copy.
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel) || die "not inside a git checkout" 3
git -C "$root" fetch -q origin main || die "could not fetch origin main" 3
[[ -z $(git -C "$root" status --porcelain --untracked-files=no) ]] || die "the checkout has tracked changes" 3
if [[ $(git -C "$root" rev-parse HEAD) != "$(git -C "$root" rev-parse origin/main)" ]]; then
  if [[ -z ${MERGE_CHECKED_REEXEC:-} ]] && git -C "$root" merge-base --is-ancestor HEAD origin/main; then
    git -C "$root" merge -q --ff-only origin/main || die "could not fast-forward the checkout" 3
    exec env MERGE_CHECKED_REEXEC=1 "$0" "$@"
  fi
  die "the checkout is not at origin/main" 3
fi

# The box's ssh function (box_ssh) comes from the Mac's own lib.
lib=$HOME/.config/central-hub/lib/pinned.zsh
[[ -f $lib ]] || die "the Mac's lib is missing" 3
box() { zsh -c '. "$1"; shift; box_ssh "$@"' _ "$lib" "$@"; }

# The box's stop (D-0042 rule 8) is a flag file; pr-merge only reads it for its own merge, so this wrapper reads it too.
halted() {
  local rc=0
  box test -e /var/lib/agent-box/passes/HALT || rc=$?
  case $rc in 0) return 0 ;; 1) return 1 ;; *) die "could not read the box's halt flag (exit $rc); nothing merged" 1 ;; esac
}
halted && die "the halt flag is set on the box; nothing merged" 1

verdict=$(box pr-merge check "$repo" "$pr" "$head" 2>&1) && rc=0 || rc=$?
echo "$verdict"
last=${verdict##*$'\n'}
# A rule 11 PR is never merged from the Mac, even with an owner-tap line: the ledger is the recorder's own word (design v6).
[[ $verdict != *"NOTE: rule 11 PR"* ]] || die "a rule 11 PR waits for the sweep; nothing merged" 1
[[ $rc -eq 0 && $last == *": GREEN" ]] || die "not GREEN (exit $rc); nothing merged. A PR that is refused waits for the sweep." 1

# The sweep posts the ledger on the PR (D-0042 rule 9); here it is printed, with its pass times, for the merge report.
box pass-record show "$repo" "$head" || die "could not read the head's ledger; nothing merged" 1
halted && die "the halt flag was set while this ran; nothing merged" 1

gh pr merge "$pr" --repo "$repo" --squash --match-head-commit "$head"
