#!/usr/bin/env bash
# run.sh's shards (run.sh <job> K/N): the N shards of a job together run every test suite exactly once, a shard
# runs a share of them, a bad shard is refused, and the steps that are not suites are suites too (so they are
# counted once). Uses HOSTS_CHECK_LIST=1, which prints each suite instead of running it.
# Usage: .github/hosts-check/tests/test_run_shards.sh
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
list() { HOSTS_CHECK_LIST=1 bash "$here/run.sh" "$@" 2>&1 | grep '^suite: ' | sort; }

for spec in "backup 3" "ansible 2" "ansible 3" "proxy 3"; do
  job=${spec% *} n=${spec#* }
  whole=$(list "$job")
  total=$(grep -c . <<< "$whole")
  joined=""
  sizes=""
  for k in $(seq 1 "$n"); do
    part=$(list "$job" "$k/$n")
    joined+="$part"$'\n'
    sizes+="$(grep -c . <<< "$part") "
  done
  union=$(grep . <<< "$joined" | sort)
  if [[ $total -gt $n && $union == "$whole" && $(grep . <<< "$joined" | sort | uniq -d | wc -l) -eq 0 ]]; then
    ok "$job in $n shards: $total suites, each exactly once (shard sizes: $sizes)"
  else bad "$job in $n shards: whole $total, union differs or repeats ($sizes)"; fi
done

bash "$here/run.sh" backup 4/3 >/dev/null 2>&1; r1=$?
bash "$here/run.sh" backup 0/3 >/dev/null 2>&1; r2=$?
bash "$here/run.sh" backup 1of3 >/dev/null 2>&1; r3=$?
if [[ $r1 -eq 2 && $r2 -eq 2 && $r3 -eq 2 ]]; then ok "a shard with K above N, K of 0 or a bad form is refused"; else bad "bad shards: $r1 $r2 $r3"; fi

exit "$fail"
