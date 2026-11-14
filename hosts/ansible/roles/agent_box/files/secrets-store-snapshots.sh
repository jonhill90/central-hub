#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store-snapshots.sh: the secrets-store wrapper's two file steps on its
# snapshot folder, run only by the wrapper under its lock (pick 239). It never reads a snapshot's contents.
#   rotate DIR KEEP          keep the newest KEEP raft-*.snap directly in DIR, with their .cluster files; older
#                            ones go. Only DIR itself is read (-maxdepth 1), so no other folder is ever touched.
#   keep DIR KEPT CLUSTER    move every raft-*.snap in DIR whose .cluster file does not name CLUSTER (or that has
#                            none), with its .cluster file, into KEPT, which rotation never reads. A file already
#                            in KEPT is never overwritten: the run stops and moves nothing more. Removing anything
#                            from KEPT is a delete under D-0042 rule 6, for the owner's tap; nothing here does it.
set -euo pipefail
umask 077

case ${1:-} in
  rotate)
    [[ $# -eq 3 && $3 =~ ^[1-9][0-9]*$ ]] || { echo "usage: secrets-store-snapshots.sh rotate DIR KEEP" >&2; exit 2; }
    dir=$2 keep=$3
    find "$dir" -maxdepth 1 -type f -name 'raft-*.snap' -printf '%f\n' | sort -r | tail -n +"$((keep + 1))" |
      while read -r f; do rm -f -- "${dir:?}/$f" "${dir:?}/$f.cluster"; done
    ;;
  keep)
    [[ $# -eq 4 && -n $4 ]] || { echo "usage: secrets-store-snapshots.sh keep DIR KEPT CLUSTER" >&2; exit 2; }
    dir=$2 kept=$3 cluster=$4
    mkdir -p -m 0700 "$kept"
    moved=0
    while read -r f; do
      c=$(cat "$dir/$f.cluster" 2>/dev/null || true)
      [[ $c == "$cluster" ]] && continue
      for g in "$f" "$f.cluster"; do
        [[ -e $dir/$g ]] || continue
        [[ ! -e $kept/$g ]] || { echo "secrets-store: $kept/$g exists already; nothing overwritten, $moved moved" >&2; exit 1; }
        mv -n -- "$dir/$g" "$kept/$g"
        [[ -e $kept/$g && ! -e $dir/$g ]] || { echo "secrets-store: could not move $g into $kept; $moved moved" >&2; exit 1; }
      done
      moved=$((moved + 1))
    done < <(find "$dir" -maxdepth 1 -type f -name 'raft-*.snap' -printf '%f\n' | sort)
    echo "$moved"
    ;;
  *) echo "usage: secrets-store-snapshots.sh rotate DIR KEEP | keep DIR KEPT CLUSTER" >&2; exit 2 ;;
esac
