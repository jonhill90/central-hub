#!/usr/bin/env bash
# Prove the newest off-box etcd backup restores (role k8s_backup, BL-0094, runbook
# docs/runbooks/test-etcd-restore.md). Runs on the control-plane node as root, from timer
# c1-restore-test.timer or by hand. It never touches the running etcd: the copy is restored into a
# temporary folder and started as a separate one-member etcd on 127.0.0.1 only, on its own ports.
#
# Passes when all of these hold:
#   1. restic brings back the newest snapshot tagged "etcd" for this host
#   2. etcdutl snapshot status reads the file and its hash matches the one saved at backup time
#   3. etcdutl snapshot restore makes a data folder from it
#   4. etcd starts on that folder and answers a health check
#   5. its revision is the snapshot's revision, and it holds the key CHECK_KEY
#
# Settings (besides those in c1-backup-lib.sh):
#   CHECK_KEY            default /registry/namespaces/kube-system (exists in every cluster)
#   RESTORE_CLIENT_PORT  default 23790     RESTORE_PEER_PORT  default 23800
#   RESTORE_TIMEOUT      seconds to wait for the copy to answer, default 60
set -euo pipefail
# shellcheck source=c1-backup-lib.sh
. "$(dirname "$0")/c1-backup-lib.sh"
backup_lib_init

ETCDCTL=${ETCDCTL:-$BACKUP_BIN/etcdctl}
ETCDUTL=${ETCDUTL:-$BACKUP_BIN/etcdutl}
ETCD=${ETCD:-$BACKUP_BIN/etcd}
CHECK_KEY=${CHECK_KEY:-/registry/namespaces/kube-system}
client=http://127.0.0.1:${RESTORE_CLIENT_PORT:-23790}
peer=http://127.0.0.1:${RESTORE_PEER_PORT:-23800}

work=$(mktemp -d "${TMPDIR:-/var/tmp}/c1-restore-test-etcd.XXXXXX")
etcd_pid=
cleanup() {
  local rc=$?
  if [ -n "$etcd_pid" ]; then
    kill "$etcd_pid" 2>/dev/null || true
    wait "$etcd_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
  exit "$rc"
}
trap cleanup EXIT
chmod 0700 "$work"

log "1. restoring the newest etcd snapshot for $BACKUP_HOST from the repository"
"$RESTIC" restore latest --host "$BACKUP_HOST" --tag etcd --target "$work/restored" --verify
db=$work/restored/etcd/snapshot.db
[ -s "$db" ] || die "the snapshot has no etcd/snapshot.db"

log "2. reading the snapshot"
"$ETCDUTL" snapshot status "$db" -w json > "$work/status.json"
read -r want_hash want_rev < <(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(s["hash"], s["revision"])' "$work/status.json")
read -r saved_hash < <(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hash"])' "$work/restored/etcd/status.json")
[ "$want_hash" = "$saved_hash" ] || die "hash $want_hash differs from $saved_hash saved at backup time"
log "   hash $want_hash, revision $want_rev"

log "3. etcdutl snapshot restore"
"$ETCDUTL" snapshot restore "$db" --data-dir "$work/data" --name restore-test \
  --initial-cluster "restore-test=$peer" --initial-advertise-peer-urls "$peer" >/dev/null 2>&1 \
  || die "etcdutl snapshot restore failed"

log "4. starting the copy on $client"
"$ETCD" --name restore-test --data-dir "$work/data" \
  --listen-client-urls "$client" --advertise-client-urls "$client" \
  --listen-peer-urls "$peer" --initial-advertise-peer-urls "$peer" \
  --initial-cluster "restore-test=$peer" > "$work/etcd.log" 2>&1 &
etcd_pid=$!
deadline=$((SECONDS + ${RESTORE_TIMEOUT:-60}))
until "$ETCDCTL" --endpoints "$client" endpoint health >/dev/null 2>&1; do
  if [ $SECONDS -ge $deadline ] || ! kill -0 "$etcd_pid" 2>/dev/null; then
    tail -20 "$work/etcd.log" >&2
    die "the restored etcd did not answer"
  fi
  sleep 1
done

log "5. checking the data"
got_rev=$("$ETCDCTL" --endpoints "$client" endpoint status -w json \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["Status"]["header"]["revision"])')
[ "$got_rev" = "$want_rev" ] || die "revision $got_rev, want $want_rev"
[ -n "$("$ETCDCTL" --endpoints "$client" get "$CHECK_KEY" --keys-only)" ] || die "key $CHECK_KEY is missing"
keys=$("$ETCDCTL" --endpoints "$client" get / --prefix --count-only -w fields | awk '/"Count"/ {print $3}')
log "PASS: etcd restore test, revision $got_rev, $keys keys under /, key $CHECK_KEY present"
