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

# This file must be the one on main: the checkout equals origin/main and no tracked file differs.
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel) || die "not inside a git checkout" 3
git -C "$root" fetch -q origin main || die "could not fetch origin main" 3
[[ $(git -C "$root" rev-parse HEAD) == "$(git -C "$root" rev-parse origin/main)" ]] || die "the checkout is not at origin/main" 3
[[ -z $(git -C "$root" status --porcelain --untracked-files=no) ]] || die "the checkout has tracked changes" 3

# The box's ssh function (box_ssh) comes from the Mac's own lib.
lib=$HOME/.config/central-hub/lib/pinned.zsh
[[ -f $lib ]] || die "the Mac's lib is missing" 3
box() { zsh -c '. "$1"; shift; box_ssh "$@"' _ "$lib" "$@"; }

verdict=$(box pr-merge check "$repo" "$pr" "$head" 2>&1) && rc=0 || rc=$?
echo "$verdict"
last=${verdict##*$'\n'}
[[ $rc -eq 0 && $last == *": GREEN" ]] || die "not GREEN (exit $rc); nothing merged. A PR that is refused waits for the sweep." 1

gh pr merge "$pr" --repo "$repo" --squash --match-head-commit "$head"
