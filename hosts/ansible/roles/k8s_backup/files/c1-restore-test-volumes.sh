#!/usr/bin/env bash
# Prove the newest off-box volume backup of this node restores (role k8s_backup, TASK-0194, runbook
# docs/runbooks/back-up-c1-off-box.md). Runs on every node as root, from timer
# c1-restore-test.timer or by hand. It restores into a temporary folder, never over a volume.
#
# Passes when all of these hold:
#   1. restic check finds the repository whole
#   2. restic brings back, from the newest snapshot tagged "volumes" for this host, each folder's
#      canary file and every database dump, and --verify reads them back against the repository
#   3. each folder's canary file holds the value c1-backup-volumes.sh wrote before that snapshot
#   4. each database dump the snapshot holds is complete (pg_dumpall's closing line)
# Only those small files are restored, not the whole snapshot: the test folder is on the node's OS
# disk, and a full restore would fill it once the volumes outgrow it, and read every byte back
# out of the off-box target each week. restic check's data subset covers the rest.
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

log "2. restoring the canaries and database dumps of the newest volume snapshot for $BACKUP_HOST"
# SELinux labels are left out: the test copy goes in a temporary folder, where SELinux refuses
# restic setting a volume's label (c1's worker, 2026-11-09: "security.selinux" could not be set on
# /var/lib/c1-data, 1 of 3790 files, exit 1). Files and contents are still checked; a real restore
# keeps the labels (docs/runbooks/back-up-c1-off-box.md, "Restore a volume").
"$RESTIC" restore latest --host "$BACKUP_HOST" --tag volumes --target "$work" --verify \
  --exclude-xattr 'security.selinux' --include '/**/.central-hub-backup-canary' --include "$BACKUP_STATE/db-dumps"

log "3. checking each folder's canary"
n=0
while IFS=$'\t' read -r path want; do
  got=$(cat "$work$path/.central-hub-backup-canary" 2>/dev/null) || die "no canary restored for $path"
  [ "$got" = "$want" ] || die "canary for $path is '$got', want '$want'"
  log "   $path: canary matches"
  n=$((n + 1))
done < "$record"

log "4. checking the database dumps"
d=0
for dump in "$work$BACKUP_STATE"/db-dumps/*.sql; do
  [ -e "$dump" ] || continue
  tail -n 5 "$dump" | grep -q '^-- PostgreSQL database cluster dump complete' || die "dump $(basename "$dump") is cut short"
  log "   $(basename "$dump"): complete, $(wc -c < "$dump") bytes"
  d=$((d + 1))
done
log "PASS: volume restore test, $n folders, $d database dumps"
