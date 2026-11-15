#!/usr/bin/env bash
# roles/agent_box/files/secrets-store-snapshots.sh (pick 239), on fake snapshot files:
#   1. rotate keeps the newest KEEP in the folder, with their .cluster files, and removes the older ones.
#   2. rotate never touches the kept folder, beside it or inside the snapshot folder.
#   3. keep moves every snapshot not of the current cluster, or with no .cluster file, with its .cluster file,
#      into the kept folder, and leaves the current cluster's in place; it prints how many it moved.
#   4. keep never overwrites a file already in the kept folder: it stops and fails.
#   5. Bad arguments are refused.
# Usage: .github/hosts-check/tests/test_secrets_store_snapshots.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
helper=$root/hosts/ansible/roles/agent_box/files/secrets-store-snapshots.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
s=$t/snaps k=$t/kept
mk() { # stamp cluster [dir]
  local d=${3:-$s}
  mkdir -p "$d"; echo "snap $1" > "$d/raft-$1.snap"
  [[ -z $2 ]] || echo "$2" > "$d/raft-$1.snap.cluster"
}
count() { find "$1" -maxdepth 1 -name 'raft-*.snap' -type f 2>/dev/null | wc -l; }

# 1 and 2
for h in 01 02 03 04 05; do mk "20261114T${h}0000Z" cluster-new; done
mk 20261113T000000Z cluster-old "$k"
mk 20261113T000000Z cluster-old "$s/inner"
bash "$helper" rotate "$s" 2
if [[ $(count "$s") == 2 && -e $s/raft-20261114T050000Z.snap && -e $s/raft-20261114T040000Z.snap.cluster && ! -e $s/raft-20261114T030000Z.snap.cluster ]]; then
  ok "1. rotate keeps the newest 2 with their .cluster files"
else bad "1. $(ls "$s")"; fi
[[ $(count "$k") == 1 && -e $k/raft-20261113T000000Z.snap.cluster && $(count "$s/inner") == 1 ]] \
  && ok "2. rotate never touches the kept folder, beside or inside" || bad "2. $(ls "$k" "$s/inner")"

# 3
rm -rf "$s" "$k"
mk 20261114T080000Z cluster-old; mk 20261114T090000Z cluster-old; mk 20261114T095000Z ""
mk 20261114T100000Z cluster-new
out=$(bash "$helper" keep "$s" "$k" cluster-new)
if [[ $out == 3 && $(count "$k") == 3 && -e $k/raft-20261114T090000Z.snap.cluster && $(count "$s") == 1 && -e $s/raft-20261114T100000Z.snap.cluster ]] &&
   [[ $(stat -c %a "$k") == 700 ]]; then
  ok "3. keep moves the other clusters' snapshots (and one with no cluster) aside, mode 700, and leaves the current one"
else bad "3. out=$out $(ls "$s" "$k")"; fi
bash "$helper" rotate "$s" 1
[[ $(count "$k") == 3 ]] && ok "3b. after keep, rotation leaves the kept snapshots alone" || bad "3b. $(ls "$k")"

# 4
mk 20261114T080000Z cluster-old
echo original > "$k/keep-check"; cp "$k/raft-20261114T080000Z.snap" "$t/before"
if bash "$helper" keep "$s" "$k" cluster-new > "$t/out" 2>&1; then bad "4. an existing file was not refused"
elif grep -q 'exists already' "$t/out" && cmp -s "$k/raft-20261114T080000Z.snap" "$t/before" && [[ -e $s/raft-20261114T080000Z.snap ]]; then
  ok "4. keep refuses to overwrite a file in the kept folder and moves nothing over it"
else bad "4. $(cat "$t/out")"; fi

# 5
r=0
bash "$helper" rotate "$s" 0 2>/dev/null && r=1
bash "$helper" keep "$s" "$k" "" 2>/dev/null && r=1
bash "$helper" delete "$s" 2>/dev/null && r=1
[[ $r == 0 ]] && ok "5. bad arguments are refused" || bad "5. a bad call was taken"
exit "$fail"
