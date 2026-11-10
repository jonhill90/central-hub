#!/usr/bin/env bash
# Restore prod's newest volume snapshot into this env's data disk, read-only (role k8s_backup,
# reader mode, TASK-0240; runbook docs/runbooks/rebuild-k8s-layer-with-one-command.md, "Restore on
# dev"). Runs as root on a dev node, from playbooks/k8s-restore.yml, before Argo CD makes the claims.
#
#   c1-restore-volumes.sh restore   restore the snapshot, then prove every folder came back whole
#   c1-restore-volumes.sh check     prove the restore is still in place (the rebuild's checks stage)
#
# Every restic call has --no-lock, so nothing is written to the repository, and the node signs in
# as a read-only identity, so nothing could be (agent pick 202).
#
# Each volume is the folder <RESTORE_PATH>/<namespace>/<claim>: local-path's pathPattern on c1 and
# dev (apps/local-path). A snapshot taken before that change holds pvc-<uid>_<namespace>_<claim>
# folders, which no claim on dev would find, so restore stops on one instead of guessing a mapping.
#
# restore passes only when all of these hold, and stops at the first that doesn't:
#   1. this node has the data disk mounted (else SKIP, exit 0: it holds no volumes)
#   2. RESTORE_PATH is empty, or holds a restore of this same snapshot (then ALREADY, nothing done)
#   3. the snapshot holds at least one <namespace>/<claim> folder and no pvc-* folder
#   4. restic restores it with --verify
#   5. each folder's file count and total bytes on disk equal restic ls of that folder in the same
#      snapshot
#   6. the canary file on disk equals the snapshot's copy of it (restic dump)
# Its record, $BACKUP_STATE/restored-volumes, keeps the snapshot ID, the canary and each folder's
# counts, and every line is printed so the rebuild's log keeps them.
#
# Settings (besides those in c1-backup-lib.sh):
#   RESTORE_SOURCE_HOST    the prod node's host name, as restic snapshots lists it (required)
#   RESTORE_PATH           the folder to restore (default /var/lib/c1-data/local-path)
#   RESTORE_SNAPSHOT       a snapshot ID, or latest (default)
#   RESTORE_REQUIRE_MOUNT  the mount point that must be there (default: RESTORE_PATH's parent;
#                          empty skips the check, for CI)
set -euo pipefail
# shellcheck source=c1-backup-lib.sh
. "$(dirname "$0")/c1-backup-lib.sh"

cmd=${1:-}
case $cmd in restore|check) ;; *) echo "usage: $0 restore|check" >&2; exit 2 ;; esac

backup_lib_init
path=${RESTORE_PATH:-/var/lib/c1-data/local-path}
path=${path%/}
record=$BACKUP_STATE/restored-volumes
canary=.central-hub-backup-canary
r() { "$RESTIC" --no-lock "$@"; }

# Files and bytes per <namespace>/<claim> folder under $path on disk, as "folder<TAB>files<TAB>bytes".
disk_counts() {
  local d
  for d in "$path"/*/*/; do
    [ -d "$d" ] || continue
    d=${d%/}
    printf '%s\t%s\t%s\n' "${d#"$path"/}" \
      "$(find "$d" -type f | wc -l | tr -d ' ')" \
      "$(find "$d" -type f -printf '%s\n' | awk '{s+=$1} END{print s+0}')"
  done
}

if [ "$cmd" = check ]; then
  [ -s "$record" ] || die "no restore recorded on $BACKUP_HOST ($record)"
  sed 's/^/   /' "$record"
  want=$(awk -F'\t' '$1 == "canary" {print $2}' "$record")
  got=$(cat "$path/$canary" 2>/dev/null) || die "no canary file in $path"
  [ "$got" = "$want" ] || die "canary in $path is '$got', the restore recorded '$want'"
  n=0
  while IFS=$'\t' read -r kind folder _; do
    [ "$kind" = folder ] || continue
    [ -d "$path/$folder" ] || die "restored folder $path/$folder is gone"
    n=$((n + 1))
  done < "$record"
  log "PASS: restore of snapshot $(awk -F'\t' '$1 == "snapshot" {print $2}' "$record") still in place, $n folders, canary matches"
  exit 0
fi

src=${RESTORE_SOURCE_HOST:?RESTORE_SOURCE_HOST is not set: the prod node whose snapshot comes back}
snap=${RESTORE_SNAPSHOT:-latest}
mnt=${RESTORE_REQUIRE_MOUNT-$(dirname "$path")}

# 1. Only a node whose data disk is mounted holds volumes; never fill the OS disk.
if [ -n "$mnt" ] && ! mountpoint -q "$mnt"; then
  echo "SKIP: $mnt is not mounted on $BACKUP_HOST, so it holds no volumes; nothing restored"
  exit 0
fi

# Which snapshot: the newest volume snapshot of the prod node, or the one asked for.
if [ "$snap" = latest ]; then
  sel=(--latest 1)
else
  sel=("$snap")
fi
id=$(r snapshots --json --host "$src" --tag volumes "${sel[@]}" | python3 -c '
import json, sys
snaps = sorted(json.load(sys.stdin) or [], key=lambda s: s["time"])
print(snaps[-1]["id"] if snaps else "")
')
[ -n "$id" ] || die "no volume snapshot of host $src ($snap) in the repository"
when=$(r snapshots --json "$id" | python3 -c 'import json, sys; print(json.load(sys.stdin)[0]["time"])')

# 2. Never over live data: an empty folder, or this same restore already done.
mkdir -p "$path"
if [ -s "$record" ]; then
  done_id=$(awk -F'\t' '$1 == "snapshot" {print $2}' "$record")
  if [ "$done_id" = "$id" ]; then
    echo "ALREADY: snapshot $id was restored on $BACKUP_HOST before; nothing done"
    sed 's/^/   /' "$record"
    echo "PASS: restore of snapshot $id in place"
    exit 0
  fi
  die "$BACKUP_HOST holds a restore of snapshot $done_id, not $id. Tear the env down to restore another."
fi
if [ -n "$(ls -A "$path")" ]; then
  die "$path on $BACKUP_HOST is not empty and holds no recorded restore; nothing was changed"
fi

# 3. What the snapshot holds under $path: files and bytes per <namespace>/<claim> folder.
work=$(mktemp -d "${TMPDIR:-/var/tmp}/c1-restore-volumes.XXXXXX")
trap 'rm -rf "$work"' EXIT
chmod 0700 "$work"
r ls --json --recursive "$id" "$path" | python3 -c '
import json, sys
base = sys.argv[1].rstrip("/") + "/"
old, folders = [], {}
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    n = json.loads(line)
    p = n.get("path", "")
    # restic 0.19 marks each line with message_type; older releases with struct_type.
    if n.get("message_type", n.get("struct_type")) != "node" or not p.startswith(base):
        continue
    parts = p[len(base):].split("/")
    if parts[0].startswith("pvc-"):
        old.append(parts[0])
        continue
    if len(parts) == 2 and n.get("type") == "dir":
        folders.setdefault("/".join(parts), [0, 0])
    elif len(parts) > 2 and n.get("type") == "file":
        f = folders.setdefault("/".join(parts[:2]), [0, 0])
        f[0] += 1
        f[1] += n.get("size", 0)
if old:
    sys.exit("OLD: %d pvc-* folders (%s ...)" % (len(set(old)), sorted(set(old))[0]))
for k in sorted(folders):
    print("%s\t%d\t%d" % (k, folders[k][0], folders[k][1]))
' "$path" > "$work/want" || die "snapshot $id holds folders named pvc-<uid>_<namespace>_<claim>: it was taken before local-path's pathPattern change. Take a new volume backup on prod after the move, then run again."
[ -s "$work/want" ] || die "snapshot $id holds no <namespace>/<claim> folder under $path"

# 4. Restore, read back against the repository. SELinux labels are left out: the nodes run SELinux
# permissive (role k8s_node, step 2), and prod's labels mean nothing on another node.
log "restoring $path from snapshot $id of $src ($when)"
r restore "$id" --target / --include "$path" --verify --exclude-xattr 'security.selinux'

# 5. Each folder on disk must hold what the snapshot holds.
disk_counts | sort > "$work/got"
if ! diff -u "$work/want" "$work/got" > "$work/diff"; then
  cat "$work/diff" >&2
  die "the restored folders differ from snapshot $id (- snapshot, + disk)"
fi

# 6. The canary: the bytes the backup wrote just before its snapshot.
want_canary=$(r dump "$id" "$path/$canary") || die "snapshot $id has no canary file in $path"
got_canary=$(cat "$path/$canary" 2>/dev/null) || die "no canary file restored in $path"
[ "$got_canary" = "$want_canary" ] || die "canary is '$got_canary', snapshot $id holds '$want_canary'"

{
  printf 'snapshot\t%s\t%s\t%s\n' "$id" "$src" "$when"
  printf 'canary\t%s\n' "$got_canary"
  sed 's/^/folder\t/' "$work/got"
} > "$record.new"
chmod 0600 "$record.new"
mv "$record.new" "$record"
cat "$record"
files=$(awk -F'\t' '{f+=$2} END{print f+0}' "$work/got")
bytes=$(awk -F'\t' '{b+=$3} END{print b+0}' "$work/got")
echo "RESTORED: snapshot $id"
echo "PASS: restored snapshot $id of $src into $path: $(wc -l < "$work/got" | tr -d ' ') folders, $files files, $bytes bytes, canary matches"
