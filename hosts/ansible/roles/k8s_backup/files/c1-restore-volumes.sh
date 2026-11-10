#!/usr/bin/env bash
# Restore prod's newest volume snapshot into this env's data disk, read-only (role k8s_backup,
# reader mode, TASK-0240; runbook docs/runbooks/rebuild-k8s-layer-with-one-command.md, "Restore on
# dev"). Runs as root on a dev node, from playbooks/k8s-restore.yml, before Argo CD makes the claims.
#
#   c1-restore-volumes.sh restore   restore the snapshot, then prove every folder came back whole
#   c1-restore-volumes.sh check     prove the restore is still in place (the rebuild's checks stage)
#   c1-restore-volumes.sh owner <namespace>/<claim> <uid>
#                                   prove one restored folder is as the app needs it (checks stage):
#                                   the folder's own owner, group and mode equal its copy in the
#                                   restored snapshot (local-path made most 0:0 777 on prod, but
#                                   not all: Grafana's is 472:472), it is not empty, and every
#                                   entry directly inside it belongs to <uid>, the Deployment's
#                                   runAsUser. A node that doesn't hold the folder says SKIP.
#
# Every restic call has --no-lock, so nothing is written to the repository, and the node signs in
# as a read-only identity, so nothing could be (agent pick 205).
#
# On dev each volume is the folder <RESTORE_PATH>/<namespace>/<claim> (local-path's pathPattern,
# switched on for dev only). Prod keeps upstream's names, <PV name>_<namespace>_<claim>, where the
# PV name is pvc-<uid> (local-path-provisioner v0.0.37, provisioner.go, Provision: folderName is
# strings.Join([PVName, PVC.Namespace, PVC.Name], "_")). Namespaces, claim names and pvc-<uid>
# are DNS names with no "_", so each such folder splits into exactly those three parts and maps to
# <namespace>/<claim>. A <namespace>/<claim> folder in the snapshot passes through as it is. Any
# other name, or two folders that map to the same <namespace>/<claim> (a leftover of a deleted
# claim, kept by reclaim policy Retain), stops the restore before anything is written.
#
# restore passes only when all of these hold, and stops at the first that doesn't:
#   1. this node has the data disk mounted (else SKIP, exit 0: it holds no volumes)
#   2. RESTORE_PATH is empty, or holds a restore of this same snapshot (then ALREADY, nothing done)
#   3. the snapshot holds at least one volume folder, every one maps to a <namespace>/<claim>,
#      and no two map to the same one
#   4. restic restores it with --verify into a staging folder on the same disk, then each folder
#      is renamed into place
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
case $cmd in restore|check|owner) ;; *) echo "usage: $0 restore|check|owner <namespace>/<claim> <uid>" >&2; exit 2 ;; esac

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

# What snapshot $1 holds under $path: each volume folder, where it goes, its files and bytes, and
# the folder's own owner and mode, as "source<TAB>destination<TAB>files<TAB>bytes<TAB>uid:gid mode".
# Exits non-zero, saying why, on a name it can't map or two folders for one claim.
snapshot_map() {
  r ls --json --recursive "$1" "$path" | python3 -c '
import json, re, sys
base = sys.argv[1].rstrip("/") + "/"
dns = re.compile(r"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$")
folders = {}   # source folder (relative) -> [files, bytes]
meta = {}      # source folder -> "uid:gid mode", the folder itself
bad = []
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
    if len(parts) == 1:
        if n.get("type") != "dir":
            continue   # the canary file
        if parts[0].startswith("pvc-"):
            folders.setdefault(parts[0], [0, 0])
            meta[parts[0]] = "%d:%d %o" % (n.get("uid", -1), n.get("gid", -1), n.get("mode", 0) & 0o777)
        continue
    # pvc-<uid>_<namespace>_<claim>/... (prod) or <namespace>/<claim>/... (dev)
    key = parts[0] if parts[0].startswith("pvc-") else "/".join(parts[:2])
    if not parts[0].startswith("pvc-") and len(parts) == 2:
        if n.get("type") == "dir":
            folders.setdefault(key, [0, 0])
            meta[key] = "%d:%d %o" % (n.get("uid", -1), n.get("gid", -1), n.get("mode", 0) & 0o777)
        else:
            bad.append(p[len(base):])
        continue
    f = folders.setdefault(key, [0, 0])
    if n.get("type") == "file":
        f[0] += 1
        f[1] += n.get("size", 0)
dest = {}
for src in sorted(folders):
    if src.startswith("pvc-"):
        bits = src.split("_")
        if len(bits) != 3 or not all(dns.match(b) for b in bits):
            bad.append(src)
            continue
        d = bits[1] + "/" + bits[2]
    else:
        ns, claim = src.split("/")
        if not (dns.match(ns) and dns.match(claim)):
            bad.append(src)
            continue
        d = src
    dest.setdefault(d, []).append(src)
if bad:
    sys.exit("UNKNOWN: folders that are not <namespace>/<claim> or pvc-<uid>_<namespace>_<claim>: %s" % ", ".join(bad))
dup = {d: s for d, s in dest.items() if len(s) > 1}
if dup:
    sys.exit("DUPLICATE: more than one folder for the same claim: %s" % "; ".join("%s <- %s" % (d, ", ".join(s)) for d, s in sorted(dup.items())))
for d in sorted(dest):
    src = dest[d][0]
    print("%s\t%s\t%d\t%d\t%s" % (src, d, folders[src][0], folders[src][1], meta.get(src, "?")))
' "$path"
}

if [ "$cmd" = owner ]; then
  rel=${2:?usage: $0 owner <namespace>/<claim> <uid>}
  uid=${3:?usage: $0 owner <namespace>/<claim> <uid>}
  case $uid in ''|*[!0-9]*) die "uid '$uid' is not a number" ;; esac
  dir=$path/$rel
  if [ ! -d "$dir" ]; then
    echo "SKIP: $dir is not on $BACKUP_HOST"
    exit 0
  fi
  [ -s "$record" ] || die "no restore recorded on $BACKUP_HOST ($record)"
  id=$(awk -F'\t' '$1 == "snapshot" {print $2}' "$record")
  work=$(mktemp -d "${TMPDIR:-/var/tmp}/c1-restore-volumes.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  snapshot_map "$id" > "$work/map" 2> "$work/map.err" || die "snapshot $id can't be mapped: $(cat "$work/map.err")"
  want=$(awk -F'\t' -v d="$rel" '$2 == d {print $5}' "$work/map")
  [ -n "$want" ] || die "$rel is not in snapshot $id"
  got="$(stat -c '%u:%g' "$dir") $(printf '%o' $((0$(stat -c '%a' "$dir") & 0777)))"
  [ "$got" = "$want" ] || die "$dir is $got (owner:group mode), its copy in snapshot $id is $want"
  n=0
  bad=()
  while IFS= read -r -d '' e; do
    n=$((n + 1))
    o=$(stat -c '%u' "$e")
    [ "$o" = "$uid" ] || bad+=("${e#"$dir"/} (uid $o)")
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0)
  [ "$n" -gt 0 ] || die "$dir is empty"
  [ "${#bad[@]}" -eq 0 ] || die "in $dir, not owned by uid $uid: ${bad[*]}"
  echo "PASS: $dir is $got (owner:group mode) as in snapshot $id, and all $n entries in it belong to uid $uid"
  exit 0
fi

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

# 3. What the snapshot holds under $path, mapped (snapshot_map).
work=$(mktemp -d "${TMPDIR:-/var/tmp}/c1-restore-volumes.XXXXXX")
trap 'rm -rf "$work"' EXIT
chmod 0700 "$work"
snapshot_map "$id" > "$work/map" 2> "$work/map.err" || die "snapshot $id can't be mapped: $(cat "$work/map.err"). Nothing was changed."
[ -s "$work/map" ] || die "snapshot $id holds no volume folder under $path"
cut -f2-4 "$work/map" | sort > "$work/want"

# 4. Restore, read back against the repository, into a staging folder beside $path on the same
# disk, then rename each folder into place (a rename on one file system moves no data). SELinux
# labels are left out: the nodes run SELinux permissive (role k8s_node, step 2), and prod's labels
# mean nothing on another node.
stage=$(dirname "$path")/.c1-restore-stage
rm -rf "$stage"
mkdir -m 0700 "$stage"
log "restoring $path from snapshot $id of $src ($when)"
r restore "$id" --target "$stage" --include "$path" --verify --exclude-xattr 'security.selinux'
while IFS=$'\t' read -r from to _; do
  mkdir -p "$path/$(dirname "$to")"
  mv "$stage$path/$from" "$path/$to"
  [ "$from" = "$to" ] || echo "mapped $from -> $to"
done < "$work/map"
if [ -e "$stage$path/$canary" ]; then mv "$stage$path/$canary" "$path/$canary"; fi
rm -rf "$stage"

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
