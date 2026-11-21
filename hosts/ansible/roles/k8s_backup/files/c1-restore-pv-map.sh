#!/usr/bin/env bash
# Which volume each claim is bound to, read from the etcd backup taken with the volume snapshot a restore will use (role
# k8s_backup; runbook docs/runbooks/rebuild-k8s-layer-with-one-command.md, "Two folders for one claim"). Runs as root on
# the control-plane node, the only one with the etcd tools, from the restore play, before the workers restore. It writes
# nothing to the repository (--no-lock, and a node signs in as a reader) and never touches the running etcd: the copy
# is restored into a temporary folder and started as a separate one-member etcd on 127.0.0.1 only, on its own ports.
#
#   c1-restore-pv-map.sh      prints, on stdout, tab-separated lines:
#     snapshot  <volume snapshot ID>
#     etcd      <etcd snapshot ID>  <its time>  <its revision>
#     pv        <namespace>/<claim>  pvc-<uid>       one per claim whose object in the backup names exactly one volume
#     ambiguous <namespace>/<claim>                  a claim whose object names more than one: no pv line, never guessed
#
# The volume snapshot is the one a restore takes (c1-backup-lib.sh, restore_snapshot_id). The etcd snapshot is the one
# whose time is nearest to it, and only within RESTORE_ETCD_WINDOW seconds (default 900): the drill that precedes a prod
# teardown takes both within minutes, and an etcd copy of another day says nothing about which volume was bound then.
# No etcd snapshot in the window stops it. The volume a claim is bound to is the pvc-<uid> in its PersistentVolumeClaim
# object (spec.volumeName), read from /registry/persistentvolumeclaims/<namespace>/<claim>; a retained, released volume
# of a deleted claim is not in that object, which is why the claim's object is read and not the volumes'.
#
# Settings (besides those in c1-backup-lib.sh): RESTORE_SOURCE_HOST (required), RESTORE_ETCD_HOST (the control plane whose etcd
# snapshots count; the restore play sets it; unset, any host's), RESTORE_SNAPSHOT (default latest),
# RESTORE_ETCD_WINDOW, RESTORE_PV_CLIENT_PORT (23791), RESTORE_PV_PEER_PORT (23801), RESTORE_TIMEOUT (60).
set -euo pipefail
# shellcheck source=c1-backup-lib.sh
. "$(dirname "$0")/c1-backup-lib.sh"
backup_lib_init

ETCDCTL=${ETCDCTL:-$BACKUP_BIN/etcdctl}
ETCDUTL=${ETCDUTL:-$BACKUP_BIN/etcdutl}
ETCD=${ETCD:-$BACKUP_BIN/etcd}
client=http://127.0.0.1:${RESTORE_PV_CLIENT_PORT:-23791}
peer=http://127.0.0.1:${RESTORE_PV_PEER_PORT:-23801}
src=${RESTORE_SOURCE_HOST:?RESTORE_SOURCE_HOST is not set: the prod node whose snapshot comes back}

work=$(mktemp -d "${TMPDIR:-/var/tmp}/c1-restore-pv-map.XXXXXX")
etcd_pid=
cleanup() {
  local rc=$?
  if [ -n "$etcd_pid" ]; then kill "$etcd_pid" 2>/dev/null || true; wait "$etcd_pid" 2>/dev/null || true; fi
  rm -rf "$work"
  exit "$rc"
}
trap cleanup EXIT
chmod 0700 "$work"

vol=$(restore_snapshot_id "$src" "${RESTORE_SNAPSHOT:-latest}") || die "no volume snapshot of host $src (${RESTORE_SNAPSHOT:-latest}) in the repository"
[ -n "$vol" ] || die "no volume snapshot of host $src (${RESTORE_SNAPSHOT:-latest}) in the repository"
vol_json=$("$RESTIC" --no-lock snapshots --json "$vol")
# Only the control plane's own etcd snapshots (RESTORE_ETCD_HOST): another host's snapshot of the same hour says nothing about this cluster.
etcd_hosts=()
[ -z "${RESTORE_ETCD_HOST:-}" ] || etcd_hosts=(--host "$RESTORE_ETCD_HOST")
etcd_json=$("$RESTIC" --no-lock snapshots --json "${etcd_hosts[@]}" --tag etcd)
pick_etcd() { # <etcd snapshots json> <single: 1 = refuse when more than one host has one in the window>
  python3 -c '
import json, sys
from datetime import datetime, timezone
def t(s):
    # restic writes nanoseconds; fromisoformat takes microseconds at most.
    s = s.replace("Z", "+00:00")
    head, _, tail = s.partition(".")
    if tail:
        frac = tail
        zone = ""
        for sep in ("+", "-"):
            if sep in tail:
                frac, zone = tail.split(sep, 1)
                zone = sep + zone
                break
        s = head + "." + frac[:6].ljust(6, "0") + zone
    d = datetime.fromisoformat(s)
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
vol = t(json.loads(sys.argv[1])[0]["time"])
window = int(sys.argv[3])
best = None
hosts = set()
for s in json.loads(sys.argv[2]) or []:
    gap = abs((t(s["time"]) - vol).total_seconds())
    if gap <= window:
        hosts.add(s.get("hostname", ""))
        if best is None or gap < best[0]:
            best = (gap, s["id"], s["time"][:19], s.get("hostname", ""))
if best and sys.argv[4] == "1" and len(hosts) != 1:
    best = None
print(*((best[1], best[2], best[3]) if best else ("", "", "")))
' "$vol_json" "$1" "${RESTORE_ETCD_WINDOW:-900}" "$2"
}
read -r eid etime ehost < <(pick_etcd "$etcd_json" 0)
if [ -z "${eid:-}" ] && [ -n "${RESTORE_ETCD_HOST:-}" ]; then
  # The named host has none in the window (a dev cluster's control plane is not named like the source's): take another
  # host's only when exactly one host has one, so it can't be a guess between clusters.
  read -r eid etime ehost < <(pick_etcd "$("$RESTIC" --no-lock snapshots --json --tag etcd)" 1)
  [ -z "${eid:-}" ] || echo "no etcd snapshot of host $RESTORE_ETCD_HOST within ${RESTORE_ETCD_WINDOW:-900}s of volume snapshot $vol; using $eid of host $ehost, the only host with one in the window" >&2
fi
[ -n "${eid:-}" ] || die "no etcd snapshot within ${RESTORE_ETCD_WINDOW:-900}s of volume snapshot $vol in the repository: which volume each claim was bound to is not on record"

"$RESTIC" --no-lock restore "$eid" --target "$work/restored" --verify >/dev/null
db=$work/restored/etcd/snapshot.db
[ -s "$db" ] || die "etcd snapshot $eid has no etcd/snapshot.db"
rev=$("$ETCDUTL" snapshot status "$db" -w json | python3 -c 'import json,sys; print(json.load(sys.stdin)["revision"])')
"$ETCDUTL" snapshot restore "$db" --data-dir "$work/data" --name pv-map \
  --initial-cluster "pv-map=$peer" --initial-advertise-peer-urls "$peer" >/dev/null 2>&1 || die "etcdutl snapshot restore failed"
"$ETCD" --name pv-map --data-dir "$work/data" \
  --listen-client-urls "$client" --advertise-client-urls "$client" \
  --listen-peer-urls "$peer" --initial-advertise-peer-urls "$peer" \
  --initial-cluster "pv-map=$peer" > "$work/etcd.log" 2>&1 &
etcd_pid=$!
deadline=$((SECONDS + ${RESTORE_TIMEOUT:-60}))
until "$ETCDCTL" --endpoints "$client" endpoint health >/dev/null 2>&1; do
  if [ $SECONDS -ge $deadline ] || ! kill -0 "$etcd_pid" 2>/dev/null; then
    tail -20 "$work/etcd.log" >&2
    die "the copy of etcd snapshot $eid did not answer"
  fi
  sleep 1
done
"$ETCDCTL" --endpoints "$client" get /registry/persistentvolumeclaims/ --prefix -w json > "$work/pvc.json"

printf 'snapshot\t%s\n' "$vol"
printf 'etcd\t%s\t%s\t%s\n' "$eid" "$etime" "$rev"
python3 -c '
import base64, json, re, sys
want = re.compile(rb"pvc-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
for kv in json.load(open(sys.argv[1])).get("kvs") or []:
    key = base64.b64decode(kv["key"]).decode()
    parts = key[len("/registry/persistentvolumeclaims/"):].split("/")
    if len(parts) != 2:
        continue
    names = sorted(set(want.findall(base64.b64decode(kv.get("value", "")))))
    claim = "/".join(parts)
    if len(names) == 1:
        print("pv\t%s\t%s" % (claim, names[0].decode()))
    elif len(names) > 1:
        print("ambiguous\t%s" % claim)
' "$work/pvc.json"
