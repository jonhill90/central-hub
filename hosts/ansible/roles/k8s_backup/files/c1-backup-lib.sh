#!/usr/bin/env bash
# Shared by the c1 backup and restore-test scripts (role k8s_backup). Sourced, not run.
# Settings come from the environment, then from the env file, so a test can set them directly.
#
#   CENTRAL_HUB_BACKUP_ENV  the env file (default /etc/central-hub/backup.env, mode 0600). It holds
#                           RESTIC_REPOSITORY, RESTIC_PASSWORD and the target's own credentials,
#                           for example AZURE_ACCOUNT_NAME and AZURE_ACCOUNT_SAS for azure:<container>:/c1.
#   BACKUP_BIN              folder with restic, etcdctl, etcdutl and etcd (default: the folder of this file)
#   BACKUP_HOST             the name snapshots are filed under (default: the short host name)
#   BACKUP_STATE            local state: the last canary values (default /var/lib/central-hub-backup)
#   BACKUP_METRICS_DIR      node_exporter's textfile folder (optional): a run that ends well writes the time there

backup_lib_init() {
  local env_file=${CENTRAL_HUB_BACKUP_ENV:-/etc/central-hub/backup.env}
  if [ -f "$env_file" ]; then
    # Only the owner may read it: it holds the repository password.
    if [ -n "$(find "$env_file" -perm /077 2>/dev/null)" ]; then
      die "$env_file can be read by others; chmod 0600 it"
    fi
    set -a
    # shellcheck source=/dev/null
    . "$env_file"
    set +a
  fi
  BACKUP_BIN=${BACKUP_BIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
  BACKUP_HOST=${BACKUP_HOST:-$(hostname -s)}
  BACKUP_STATE=${BACKUP_STATE:-/var/lib/central-hub-backup}
  RESTIC=${RESTIC:-$BACKUP_BIN/restic}
  : "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY is not set (env file ${env_file})}"
  : "${RESTIC_PASSWORD:?RESTIC_PASSWORD is not set (env file ${env_file})}"
  export RESTIC_REPOSITORY RESTIC_PASSWORD
  mkdir -p "$BACKUP_STATE"
  chmod 0700 "$BACKUP_STATE"
}

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

# After a run ends well: c1_backup_last_success_timestamp_seconds{kind="<kind>"} in
# $BACKUP_METRICS_DIR/c1-backup-<kind>.prom, for node_exporter's textfile collector, so Prometheus
# can tell when the last good run was (apps/monitoring-extras, C1BackupStale). Written to a temporary
# file and renamed, so the collector never reads half a file. Not set: nothing. A failed write is
# logged and does not fail the backup that already ended well.
backup_mark_success() {
  local kind=$1 dir=${BACKUP_METRICS_DIR:-} f tmp
  [ -n "$dir" ] || return 0
  f=$dir/c1-backup-$kind.prom
  tmp=$f.$$
  if { printf '# HELP c1_backup_last_success_timestamp_seconds When a c1 backup or restore test last ended well.\n'
       printf '# TYPE c1_backup_last_success_timestamp_seconds gauge\n'
       printf 'c1_backup_last_success_timestamp_seconds{kind="%s"} %s\n' "$kind" "$(date +%s)"
     } > "$tmp" && chmod 0644 "$tmp" && mv "$tmp" "$f"; then
    log "recorded the $kind run's time in $f"
  else
    rm -f "$tmp"
    log "could not write $f; the $kind run itself ended well"
  fi
}
die() { log "FAIL: $*" >&2; exit 1; }

# Make the repository the first time; leave it alone after that. Only restic's exit code 10, "repository
# does not exist" (restic 0.17 and later), makes one: any other failure to read it (the network, the
# sign-in, a wrong password, 12) stops the run: `init` is refused on a repository that is there (c1,
# 2026-11-18 07:25 UTC), and the backup could not use it anyway.
restic_ensure_repo() {
  local rc=0 err
  err=$("$RESTIC" cat config 2>&1 >/dev/null) || rc=$?
  case $rc in
    0) return 0 ;;
    10) log "no repository at the target yet: making one"
        "$RESTIC" init ;;
    *) die "could not read the repository (restic exit $rc), so it was left alone: $(tail -n 3 <<<"$err" | tr '\n' ' ')" ;;
  esac
}

# forget + prune with the retention from the env file (agent pick: 7 daily, 4 weekly, 6 monthly).
# While $BACKUP_STATE/forget-hold exists it forgets nothing: a rebuilt prod's restore writes it on every node, and the checks stage
# removes it once every restored folder has been proven. Until then the snapshot the restore came from, and the etcd snapshot that
# said which volumes were bound, are the only good copy, and the retention (the newest of each day, week and month wins) would
# forget them at the first backup of the rebuilt nodes.
restic_retention() {
  local tag=$1
  if [ -e "$BACKUP_STATE/forget-hold" ]; then
    log "retention skipped: $BACKUP_STATE/forget-hold is set (the restore has not been proven yet); nothing was forgotten"
    return 0
  fi
  "$RESTIC" forget --host "$BACKUP_HOST" --tag "$tag" --group-by host,tags \
    --keep-daily "${BACKUP_KEEP_DAILY:-7}" --keep-weekly "${BACKUP_KEEP_WEEKLY:-4}" \
    --keep-monthly "${BACKUP_KEEP_MONTHLY:-6}" --prune
}

# The volume snapshot a restore takes: <source host> <snapshot ID, or latest>. Prints its full ID. A given ID (or its
# prefix) must be a volume snapshot of that host, else this fails: restic matches the filters before it takes the ID.
# Read-only (--no-lock). The rebuild of prod passes the ID of the snapshot it backed up before the teardown, so a later
# snapshot of rebuilt, empty nodes is never the one that comes back.
restore_snapshot_id() {
  local src=$1 snap=$2 sel out
  if [ "$snap" = latest ]; then sel=(--latest 1); else sel=("$snap"); fi
  out=$("$RESTIC" --no-lock snapshots --json --host "$src" --tag volumes "${sel[@]}") || return 1
  python3 -c '
import json, sys
snaps = sorted(json.load(sys.stdin) or [], key=lambda s: s["time"])
print(snaps[-1]["id"] if snaps else "")
' <<< "$out"
}
