#!/usr/bin/env bash
# Shared by the c1 backup and restore-test scripts (role k8s_backup). Sourced, not run.
# Settings come from the environment, then from the env file, so a test can set them directly.
#
#   CENTRAL_HUB_BACKUP_ENV  the env file (default /etc/central-hub/backup.env, mode 0600). It holds
#                           RESTIC_REPOSITORY, RESTIC_PASSWORD and the target's own credentials,
#                           for example AZURE_ACCOUNT_NAME and AZURE_ACCOUNT_KEY for azure:<container>:/c1.
#   BACKUP_BIN              folder with restic, etcdctl, etcdutl and etcd (default: the folder of this file)
#   BACKUP_HOST             the name snapshots are filed under (default: the short host name)
#   BACKUP_STATE            local state: the last canary values (default /var/lib/central-hub-backup)

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
die() { log "FAIL: $*" >&2; exit 1; }

# Make the repository the first time; leave it alone after that.
restic_ensure_repo() {
  if "$RESTIC" cat config >/dev/null 2>&1; then
    return 0
  fi
  log "no repository at the target yet: making one"
  "$RESTIC" init
}

# forget + prune with the retention from the env file (agent pick: 7 daily, 4 weekly, 6 monthly).
restic_retention() {
  local tag=$1
  "$RESTIC" forget --host "$BACKUP_HOST" --tag "$tag" --group-by host,tags \
    --keep-daily "${BACKUP_KEEP_DAILY:-7}" --keep-weekly "${BACKUP_KEEP_WEEKLY:-4}" \
    --keep-monthly "${BACKUP_KEEP_MONTHLY:-6}" --prune
}
