#!/usr/bin/env bash
# Prove the newest off-box volume backup of this node restores (role k8s_backup, TASK-0139, runbook
# docs/runbooks/back-up-c1-off-box.md). Runs on every node as root, from timer
# c1-restore-test.timer or by hand. It restores into a temporary folder, never over a volume.
#
# Passes when all of these hold:
#   1. restic check finds the repository whole
#   2. restic brings back the newest snapshot tagged "volumes" for this host, and --verify reads
#      every restored file back against the repository
#   3. each folder's canary file holds the value c1-backup-volumes.sh wrote before that snapshot
# A node with no canary record (it has no volume folders) passes with nothing to test.
#
# Settings: those in c1-backup-lib.sh. RESTORE_READ_DATA_SUBSET (default 2%) is the share of the
# repository's data that restic check reads back in full on each run.
set -euo pipefail
# shellcheck source=c1-backup-lib.sh
. "$(dirname "$0")/c1-backup-lib.sh"
backup_lib_init

record=$BACKUP_STATE/canary-volumes
if [ ! -s "$record" ]; then
  log "PASS: no volume backups recorded on $BACKUP_HOST; nothing to test"
  exit 0
fi

work=$(mktemp -d "${TMPDIR:-/var/tmp}/c1-restore-test-volumes.XXXXXX")
trap 'rm -rf "$work"' EXIT
chmod 0700 "$work"

log "1. restic check"
"$RESTIC" check --read-data-subset "${RESTORE_READ_DATA_SUBSET:-2%}"

log "2. restoring the newest volume snapshot for $BACKUP_HOST"
"$RESTIC" restore latest --host "$BACKUP_HOST" --tag volumes --target "$work" --verify

log "3. checking each folder's canary"
n=0
while IFS=$'\t' read -r path want; do
  got=$(cat "$work$path/.central-hub-backup-canary" 2>/dev/null) || die "no canary restored for $path"
  [ "$got" = "$want" ] || die "canary for $path is '$got', want '$want'"
  files=$(find "$work$path" -type f | wc -l)
  log "   $path: canary matches, $files files"
  n=$((n + 1))
done < "$record"
log "PASS: volume restore test, $n folders"
