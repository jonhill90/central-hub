#!/usr/bin/env bash
# Back up c1's persistent volumes off the box (role k8s_backup, TASK-0194, runbook
# docs/runbooks/back-up-c1-off-box.md). Runs on every node as root, from timer
# c1-backup-volumes.timer. A node that holds none of the folders backs up nothing and exits 0.
#
# Every volume from the default StorageClass is a folder under /var/lib/c1-data/local-path on the
# node that holds it (role k8s_storage); Keycloak's database is a static volume in
# /var/lib/central-hub/identity-postgres. One restic snapshot, tag "volumes", holds all of a
# node's folders. Files are read while the apps run, and restic reads them one after another, so
# a running database's files in the snapshot are not a usable backup: PostgreSQL's docs ("File
# System Level Backup") say the server must be stopped, or the copy must be one atomic snapshot.
# So before the copy, each running PostgreSQL container on this node (crictl, container name
# "postgres") is dumped with pg_dumpall into $BACKUP_STATE/db-dumps/<namespace>_<pod>.sql, and that
# folder goes into the same snapshot. The dump is what a database is restored from (agent pick 190).
#
# Each run first writes a new random canary file into each folder, and keeps its value in
# $BACKUP_STATE/canary-volumes. c1-restore-test-volumes.sh brings the snapshot back and checks the
# canaries, so a test proves the bytes that left the node come back.
#
# Settings (besides those in c1-backup-lib.sh):
#   BACKUP_VOLUME_PATHS  space-separated folders (default "/var/lib/c1-data/local-path
#                        /var/lib/central-hub/identity-postgres")
#   BACKUP_CRICTL        crictl (default: crictl on the PATH; none means no database dumps)
set -euo pipefail
# shellcheck source=c1-backup-lib.sh
. "$(dirname "$0")/c1-backup-lib.sh"
backup_lib_init

read -r -a wanted <<< "${BACKUP_VOLUME_PATHS:-/var/lib/c1-data/local-path /var/lib/central-hub/identity-postgres}"
paths=()
for p in "${wanted[@]}"; do
  [ -d "$p" ] && paths+=("$p")
done
if [ ${#paths[@]} -eq 0 ]; then
  log "no volume folders on $BACKUP_HOST (${wanted[*]}); nothing to back up"
  exit 0
fi

# Dump every running PostgreSQL container on this node. The official image trusts its own Unix
# socket, so pg_dumpall needs no password. A failed dump fails the run, after the file backup.
dumps=$BACKUP_STATE/db-dumps
dump_failed=0
mkdir -p "$dumps"
chmod 0700 "$dumps"
rm -f "$dumps"/*.sql
crictl_bin=${BACKUP_CRICTL:-$(command -v crictl || true)}
if [ -n "$crictl_bin" ]; then
  while read -r id ns pod; do
    [ -n "$id" ] || continue
    out="$dumps/${ns}_${pod}.sql"
    log "dumping PostgreSQL in $ns/$pod"
    # shellcheck disable=SC2016  # $POSTGRES_USER is the container's, not this shell's
    if "$crictl_bin" exec "$id" sh -c 'pg_dumpall -U "$POSTGRES_USER"' > "$out.part" \
      && grep -q '^-- PostgreSQL database cluster dump complete' "$out.part"; then
      mv "$out.part" "$out"
      log "   $(wc -c < "$out") bytes"
    else
      rm -f "$out.part"
      log "FAIL: pg_dumpall in $ns/$pod did not finish" >&2
      dump_failed=1
    fi
  done < <("$crictl_bin" ps --name '^postgres$' --state running -o json | python3 -c '
import json, sys
for c in json.load(sys.stdin).get("containers", []):
    l = c.get("labels", {})
    print(c["id"], l.get("io.kubernetes.pod.namespace", "none"), l.get("io.kubernetes.pod.name", c["id"][:12]))
')
else
  log "no crictl on $BACKUP_HOST; no database dumps"
fi
# The dumps go in the same snapshot, but get no canary of their own: they are checked by content.
extra=()
if ls "$dumps"/*.sql >/dev/null 2>&1; then
  extra=("$dumps")
fi

canary=$(head -c 24 /dev/urandom | base64 | tr -d '/+=')
: > "$BACKUP_STATE/canary-volumes.new"
for p in "${paths[@]}"; do
  printf '%s\n' "$canary" > "$p/.central-hub-backup-canary"
  printf '%s\t%s\n' "$p" "$canary" >> "$BACKUP_STATE/canary-volumes.new"
done

restic_ensure_repo
log "backing up ${paths[*]} ${extra[*]}"
"$RESTIC" backup --host "$BACKUP_HOST" --tag volumes --tag c1 --one-file-system "${paths[@]}" "${extra[@]}"
mv "$BACKUP_STATE/canary-volumes.new" "$BACKUP_STATE/canary-volumes"
restic_retention volumes
[ "$dump_failed" = 0 ] || die "a database dump failed; the files were backed up, the dump was not"
log "volume backup done"
