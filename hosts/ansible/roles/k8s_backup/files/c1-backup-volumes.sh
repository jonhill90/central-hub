#!/usr/bin/env bash
# Back up c1's persistent volumes off the box (role k8s_backup, TASK-0194, runbook
# docs/runbooks/back-up-c1-off-box.md). Runs on every node as root, from timer
# c1-backup-volumes.timer. A node that holds none of the folders backs up nothing and exits 0.
#
# Every volume from the default StorageClass is a folder under /var/lib/c1-data/local-path on the
# node that holds it (role k8s_storage); Keycloak's database is a static volume in
# /var/lib/central-hub/identity-postgres. One restic snapshot, tag "volumes", holds all of a
# node's folders. Files are read while the apps run, so a database's copy is crash-consistent at
# best: PostgreSQL replays its WAL on start, which is what it does after a power cut.
#
# Each run first writes a new random canary file into each folder, and keeps its value in
# $BACKUP_STATE/canary-volumes. c1-restore-test-volumes.sh brings the snapshot back and checks the
# canaries, so a test proves the bytes that left the node come back.
#
# Settings (besides those in c1-backup-lib.sh):
#   BACKUP_VOLUME_PATHS  space-separated folders (default "/var/lib/c1-data/local-path
#                        /var/lib/central-hub/identity-postgres")
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

canary=$(head -c 24 /dev/urandom | base64 | tr -d '/+=')
: > "$BACKUP_STATE/canary-volumes.new"
for p in "${paths[@]}"; do
  printf '%s\n' "$canary" > "$p/.central-hub-backup-canary"
  printf '%s\t%s\n' "$p" "$canary" >> "$BACKUP_STATE/canary-volumes.new"
done

restic_ensure_repo
log "backing up ${paths[*]}"
"$RESTIC" backup --host "$BACKUP_HOST" --tag volumes --tag c1 --one-file-system "${paths[@]}"
mv "$BACKUP_STATE/canary-volumes.new" "$BACKUP_STATE/canary-volumes"
restic_retention volumes
log "volume backup done"
