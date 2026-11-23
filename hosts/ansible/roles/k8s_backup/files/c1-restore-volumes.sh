#!/usr/bin/env bash
# Restore prod's newest volume snapshot into this env's data disk, read-only (role k8s_backup,
# reader mode, TASK-0240; runbook docs/runbooks/rebuild-k8s-layer-with-one-command.md, "Restore on
# dev"). Runs as root on a dev node, from playbooks/k8s-restore.yml, before Argo CD makes the claims.
#
#   c1-restore-volumes.sh restore   restore the snapshot, then prove every folder came back whole
#   c1-restore-volumes.sh check     prove the restore is still in place (the rebuild's checks stage)
#   c1-restore-volumes.sh plan      read only, for the drill before a prod teardown: the folder mapping the restore will
#                                   run, on the newest volume snapshot of the source host (or RESTORE_SNAPSHOT). With
#                                   RESTORE_PLAN_STRICT=1 it fails if any claim has more than one folder in the snapshot
#                                   or any name can't be mapped, even where the etcd record could settle it: a prod
#                                   that is about to be torn down is cleaned first, not trusted to a later guess.
#                                   Prints "PASS: plan: snapshot <full ID>: ..." or the reason it fails.
#   c1-restore-volumes.sh inspect   read only: what the snapshot holds, folder by folder (files, bytes, newest file
#                                   time), which folder each claim would take, and why a claim with several is not
#                                   resolved. It writes nothing, needs no mounted data disk and no empty folder.
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
# other name stops the restore before anything is written. So do two folders that map to the same
# <namespace>/<claim> (a leftover of a deleted claim, kept by reclaim policy Retain), unless the etcd
# backup taken with this snapshot names the volume the claim was bound to (RESTORE_PV_MAP, made on the
# control plane by c1-restore-pv-map.sh): then that one folder is restored and the others are not,
# whatever their sizes or times. A claim with no such record, a record for another snapshot, a claim
# the etcd backup names two volumes for, or a bound volume whose folder is not in the snapshot stops
# the restore as before. A guess by size or time is never made.
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
#   RESTORE_SNAPSHOT       a snapshot ID, or latest (default). The rebuild of prod always passes the ID of the
#                          snapshot it backed up before the teardown: "latest" there could be a snapshot of the
#                          rebuilt, empty nodes
#   RESTORE_PV_MAP         the file c1-restore-pv-map.sh printed (optional; only read for a claim with two or
#                          more folders)
#   RESTORE_REQUIRE_MOUNT  the mount point that must be there (default: RESTORE_PATH's parent;
#                          empty skips the check, for CI)
set -euo pipefail
# shellcheck source=c1-backup-lib.sh
. "$(dirname "$0")/c1-backup-lib.sh"

cmd=${1:-}
case $cmd in restore|check|owner|inspect|plan) ;; *) echo "usage: $0 restore|check|owner <namespace>/<claim> <uid>|inspect|plan" >&2; exit 2 ;; esac

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
# Exits non-zero, saying why, on a name it can't map or two folders for one claim that the etcd backup (RESTORE_PV_MAP)
# doesn't settle. "snapshot_map <ID> inspect" prints every folder instead, "source<TAB>destination<TAB>files<TAB>bytes<TAB>
# newest file time<TAB>what the restore does with it", and fails on nothing.
snapshot_map() {
  r ls --json --recursive "$1" "$path" | python3 -c '
import json, re, sys
base = sys.argv[1].rstrip("/") + "/"
pvfile, snapid, mode = sys.argv[2], sys.argv[3], sys.argv[4]
dns = re.compile(r"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$")
folders = {}   # source folder (relative) -> [files, bytes]
meta = {}      # source folder -> "uid:gid mode", the folder itself
newest = {}    # source folder -> newest mtime of anything inside it (first 19 characters, restic writes UTC)
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
    if n.get("type") != "dir" and n.get("mtime", "")[:19] > newest.get(key, ""):
        newest[key] = n["mtime"][:19]
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
# The etcd backup taken with this snapshot: which volume each claim was bound to (c1-restore-pv-map.sh).
pv, ambiguous, pv_snap = {}, set(), ""
if pvfile:
    try:
        recs = open(pvfile).read().splitlines()
    except OSError:
        recs = []
    for rec in recs:
        f = rec.split("\t")
        if f[0] == "snapshot" and len(f) == 2:
            pv_snap = f[1]
        elif f[0] == "pv" and len(f) == 3:
            pv[f[1]] = f[2]
        elif f[0] == "ambiguous" and len(f) == 2:
            ambiguous.add(f[1])
def settle(d, srcs):
    """The one folder the etcd backup binds claim d to, or (None, why not)."""
    if not pv_snap:
        return None, "no record of which volume it was bound to (no etcd backup read)"
    if pv_snap != snapid:
        return None, "the record of its volume is for snapshot %s, not %s" % (pv_snap[:12], snapid[:12])
    if d in ambiguous:
        return None, "the etcd backup names more than one volume for it"
    name = pv.get(d)
    if not name:
        return None, "the etcd backup holds no bound volume for it"
    want = name + "_" + d.replace("/", "_")
    if want not in srcs:
        return None, "the etcd backup binds it to %s, which has no folder in the snapshot" % name
    return want, ""
if mode == "inspect":
    for d in sorted(dest):
        srcs = dest[d]
        chosen, why = (srcs[0], "") if len(srcs) == 1 else settle(d, srcs)
        for src in srcs:
            role = "only folder for the claim" if len(srcs) == 1 else ("BOUND: restored" if src == chosen else ("not bound: left out" if chosen else "NOT SETTLED: %s" % why))
            print("%s\t%s\t%d\t%d\t%s\t%s" % (src, d, folders[src][0], folders[src][1], newest.get(src, "-"), role))
    for src in bad:
        print("%s\t?\t-\t-\t-\tUNKNOWN NAME: stops the restore" % src)
    sys.exit(0)
if bad:
    sys.exit("UNKNOWN: folders that are not <namespace>/<claim> or pvc-<uid>_<namespace>_<claim>: %s" % ", ".join(bad))
dups = {d: s for d, s in dest.items() if len(s) > 1}
stuck = []
for d, srcs in sorted(dups.items()):
    chosen, why = settle(d, srcs)
    if chosen:
        dest[d] = [chosen]
    else:
        stuck.append("%s <- %s (%s)" % (d, ", ".join(srcs), why))
if stuck:
    sys.exit("DUPLICATE: more than one folder for the same claim: %s" % "; ".join(stuck))
for d in sorted(dest):
    src = dest[d][0]
    print("%s\t%s\t%d\t%d\t%s" % (src, d, folders[src][0], folders[src][1], meta.get(src, "?")))
' "$path" "${RESTORE_PV_MAP:-}" "$1" "${2:-map}"
}

# snapshot_map, and for a claim with two or more folders the etcd backup's record of the volume it was bound to
# (c1-restore-pv-map.sh, which needs the etcd tools; run only when a claim has several folders, so a restore without
# any pays nothing). The record is kept in $BACKUP_STATE/pv-map, so the checks stage's `owner` maps the same folders.
# Notes go to stderr; on failure stderr says why (a failed record read is added to the DUPLICATE line, and nothing is guessed).
settled_map() {
  local id=$1 out err given=${RESTORE_PV_MAP:+1}
  [ -n "${RESTORE_PV_MAP:-}" ] || { [ -s "$BACKUP_STATE/pv-map" ] && RESTORE_PV_MAP=$BACKUP_STATE/pv-map || true; }
  out=$work/map.try err=$work/map.try.err
  if snapshot_map "$id" > "$out" 2> "$err"; then cat "$out"; return 0; fi
  if grep -q '^DUPLICATE' "$err" && [ -z "$given" ] && [ -x "$BACKUP_BIN/c1-restore-pv-map.sh" ]; then
    echo "more than one folder for one claim: reading which volume the etcd backup taken with snapshot $id bound each claim to" >&2
    if RESTORE_SOURCE_HOST=${RESTORE_SOURCE_HOST:-} RESTORE_SNAPSHOT=$id RESTORE_ETCD_HOST=${RESTORE_ETCD_HOST:-} "$BACKUP_BIN/c1-restore-pv-map.sh" > "$work/pv-map" 2> "$work/pv-map.err"; then
      RESTORE_PV_MAP=$work/pv-map
      cat "$work/pv-map.err" >&2
      grep -P '^etcd\t' "$work/pv-map" | sed 's/^/etcd backup used (id, time, revision): /' >&2 || true
      if snapshot_map "$id" > "$out" 2> "$err"; then
        install -m 0600 "$work/pv-map" "$BACKUP_STATE/pv-map"
        cat "$out"; return 0
      fi
    else
      printf 'the etcd record could not be read: %s\n' "$(tail -n 2 "$work/pv-map.err" | tr '\n' ' ')" >> "$err"
    fi
  fi
  cat "$err" >&2
  return 1
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
  settled_map "$id" > "$work/map" 2> "$work/map.err" || die "snapshot $id can't be mapped: $(cat "$work/map.err")"
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
  how=matches
  if [ "$got" != "$want" ]; then
    # Every volume backup writes a new canary into each folder (c1-backup-volumes.sh), so one that ran after the restore (the prod
    # backup-drill stage, or the nightly timer) changes the file, and the restored data is still there. That is accepted only when this
    # node recorded the canary after the restore (canary-volumes is replaced only after its snapshot succeeded, and is newer than the
    # restore's record) AND the newest volumes snapshot of this node holds exactly the canary on disk (read from the repository). A
    # canary nobody recorded, or one the snapshot does not hold, fails as it always did.
    backups=$BACKUP_STATE/canary-volumes
    later=$(awk -F'\t' -v p="$path" '$1 == p {print $2}' "$backups" 2>/dev/null || true)
    [ -n "$later" ] && [ "$got" = "$later" ] && [ "$backups" -nt "$record" ] ||
      die "canary in $path is '$got', the restore recorded '$want', and no backup of this node recorded it after the restore"
    held=$(r dump --host "$BACKUP_HOST" --tag volumes latest "$path/$canary" 2>/dev/null) ||
      die "canary in $path is '$got', not the restore's '$want'; the newest volumes snapshot of $BACKUP_HOST could not be read to confirm it"
    [ "$held" = "$got" ] || die "canary in $path is '$got', the restore recorded '$want', and the newest volumes snapshot of $BACKUP_HOST holds '$held'"
    how="matches the one the node's own backup recorded after the restore, and the newest volumes snapshot holds it"
  fi
  n=0
  while IFS=$'\t' read -r kind folder _; do
    [ "$kind" = folder ] || continue
    [ -d "$path/$folder" ] || die "restored folder $path/$folder is gone"
    n=$((n + 1))
  done < "$record"
  log "PASS: restore of snapshot $(awk -F'\t' '$1 == "snapshot" {print $2}' "$record") still in place, $n folders, canary $how"
  exit 0
fi

src=${RESTORE_SOURCE_HOST:?RESTORE_SOURCE_HOST is not set: the prod node whose snapshot comes back}
snap=${RESTORE_SNAPSHOT:-latest}
mnt=${RESTORE_REQUIRE_MOUNT-$(dirname "$path")}

# 1. Only a node whose data disk is mounted holds volumes; never fill the OS disk. (inspect reads only: it needs no disk.)
if [ "$cmd" != inspect ] && [ "$cmd" != plan ] && [ -n "$mnt" ] && ! mountpoint -q "$mnt"; then
  echo "SKIP: $mnt is not mounted on $BACKUP_HOST, so it holds no volumes; nothing restored"
  exit 0
fi

# Which snapshot: the newest volume snapshot of the prod node, or the one asked for (the ID the rebuild of prod pins).
id=$(restore_snapshot_id "$src" "$snap") || die "no volume snapshot of host $src ($snap) in the repository"
[ -n "$id" ] || die "no volume snapshot of host $src ($snap) in the repository"
when=$(r snapshots --json "$id" | python3 -c 'import json, sys; print(json.load(sys.stdin)[0]["time"])')

if [ "$cmd" = plan ]; then
  work=$(mktemp -d "${TMPDIR:-/var/tmp}/c1-restore-volumes.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  chmod 0700 "$work"
  snapshot_map "$id" inspect > "$work/all"
  n=$(wc -l < "$work/all" | tr -d ' ')
  [ "$n" -gt 0 ] || die "plan: snapshot $id holds no volume folder under $path"
  unknown=$(awk -F'\t' '$2 == "?" {print $1}' "$work/all" | tr '\n' ' ')
  [ -z "$unknown" ] || die "plan: snapshot $id holds folders that are not <namespace>/<claim> or pvc-<uid>_<namespace>_<claim>: $unknown"
  many=$(awk -F'\t' '{f[$2] = f[$2] " " $1; c[$2]++} END {for (k in c) if (c[k] > 1) printf "%s <-%s; ", k, f[k]}' "$work/all")
  if [ -n "$many" ]; then
    if [ "${RESTORE_PLAN_STRICT:-}" = 1 ]; then
      die "plan: snapshot $id has more than one folder for the same claim: $many. Clean them up on the live nodes before a teardown; nothing was changed."
    fi
    settled_map "$id" > "$work/map" 2> "$work/map.err" || die "plan: snapshot $id can't be mapped: $(cat "$work/map.err")"
  fi
  claims=$(cut -f2 "$work/all" | sort -u | wc -l | tr -d ' ')
  if [ -n "$many" ]; then note=" (more than one folder for: $many settled by the etcd record)"; else note=", no claim has more than one folder"; fi
  echo "PASS: plan: snapshot $id: $n folders map to $claims claims$note"
  exit 0
fi

if [ "$cmd" = inspect ]; then
  echo "snapshot	$id	$src	$when"
  work=$(mktemp -d "${TMPDIR:-/var/tmp}/c1-restore-volumes.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  chmod 0700 "$work"
  if [ -z "${RESTORE_PV_MAP:-}" ] && [ -x "$BACKUP_BIN/c1-restore-pv-map.sh" ] &&
     RESTORE_SOURCE_HOST=$src RESTORE_SNAPSHOT=$id "$BACKUP_BIN/c1-restore-pv-map.sh" > "$work/pv-map" 2> "$work/pv-map.err"; then
    RESTORE_PV_MAP=$work/pv-map
  elif [ -z "${RESTORE_PV_MAP:-}" ] && [ -s "$work/pv-map.err" ]; then
    echo "pv-record	could not be read: $(tail -n 2 "$work/pv-map.err" | tr '\n' ' ')"
  fi
  if [ -n "${RESTORE_PV_MAP:-}" ] && [ -s "$RESTORE_PV_MAP" ]; then
    sed -n '/^\(snapshot\|etcd\)\t/ s/^/pv-record\t/p' "$RESTORE_PV_MAP"
  else
    echo "pv-record	none"
  fi
  echo "folder	claim	files	bytes	newest file (UTC)	what the restore does"
  snapshot_map "$id" inspect
  exit 0
fi

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
settled_map "$id" > "$work/map" 2> "$work/map.err" || die "snapshot $id can't be mapped: $(cat "$work/map.err"). Nothing was changed."
[ ! -s "$work/map.err" ] || sed 's/^/note: /' "$work/map.err"
[ -s "$work/map" ] || die "snapshot $id holds no volume folder under $path"
# Claims another env's store must not hold (RESTORE_SKIP_CLAIMS, "<namespace>/<claim>" separated by spaces): when the snapshot is
# another node's (RESTORE_SOURCE_HOST is not this node), their folders are not restored, so dev gets neither prod's secrets nor
# data that only opens with prod's seal key. A restore of this node's own snapshot (prod's rebuild) skips nothing.
include_args=(--include "$path")
if [ -n "${RESTORE_SKIP_CLAIMS:-}" ] && [ "$src" != "$BACKUP_HOST" ]; then
  skipped=
  for claim in $RESTORE_SKIP_CLAIMS; do
    awk -F'\t' -v c="$claim" '$2 == c {found = 1} END {exit !found}' "$work/map" || continue
    skipped="$skipped $(awk -F'\t' -v c="$claim" '$2 == c {printf "%s ", $1}' "$work/map")"
    awk -F'\t' -v c="$claim" '$2 != c' "$work/map" > "$work/map.kept" && mv "$work/map.kept" "$work/map"
  done
  [ -z "$skipped" ] || echo "SKIP: folders of claims not restored on this env (RESTORE_SKIP_CLAIMS $RESTORE_SKIP_CLAIMS):$skipped"
  [ -s "$work/map" ] || die "snapshot $id holds no volume folder under $path once RESTORE_SKIP_CLAIMS is applied"
  # restic takes includes or excludes, not both: with claims left out, name each folder that stays (and the canary).
  if [ -n "$skipped" ]; then
    include_args=(--include "$path/$canary")
    while IFS=$'\t' read -r from _; do include_args+=(--include "$path/$from"); done < "$work/map"
  fi
fi
cut -f2-4 "$work/map" | sort > "$work/want"

# 4. Restore, read back against the repository, into a staging folder beside $path on the same
# disk, then rename each folder into place (a rename on one file system moves no data). SELinux
# labels are left out: the nodes run SELinux permissive (role k8s_node, step 2), and prod's labels
# mean nothing on another node.
stage=$(dirname "$path")/.c1-restore-stage
rm -rf "$stage"
mkdir -m 0700 "$stage"
log "restoring $path from snapshot $id of $src ($when)"
r restore "$id" --target "$stage" "${include_args[@]}" --verify --exclude-xattr 'security.selinux'
while IFS=$'\t' read -r from to _; do
  mkdir -p "$path/$(dirname "$to")"
  mv "$stage$path/$from" "$path/$to"
  [ "$from" = "$to" ] || echo "mapped $from -> $to"
done < "$work/map"
# Folders of a claim with several that were not the bound one stay in the staging folder, which goes. They are named.
for left in "$stage$path"/pvc-*; do
  [ -d "$left" ] && echo "not restored: ${left##*/} (not the volume its claim was bound to)"
done
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
# The nodes' backups forget nothing until the checks stage has proven this restore (c1-backup-lib.sh, restic_retention).
printf 'held by the restore of snapshot %s at %s\n' "$id" "$(date -u +%FT%TZ)" > "$BACKUP_STATE/forget-hold"
cat "$record"
files=$(awk -F'\t' '{f+=$2} END{print f+0}' "$work/got")
bytes=$(awk -F'\t' '{b+=$3} END{print b+0}' "$work/got")
echo "RESTORED: snapshot $id"
echo "PASS: restored snapshot $id of $src into $path: $(wc -l < "$work/got" | tr -d ' ') folders, $files files, $bytes bytes, canary matches"
