#!/usr/bin/env bash
# The c1 backups' success times for node-exporter (role k8s_backup, c1-backup-lib.sh backup_mark_success):
#   1. With BACKUP_METRICS_DIR set, it writes c1-backup-<kind>.prom, mode 0644, in the textfile
#      collector's format (promtool check metrics), with the kind and a current time, and leaves no
#      temporary file behind.
#   2. Without BACKUP_METRICS_DIR it writes nothing and returns 0.
#   3. A folder it can't write to is logged and returns 0, so a backup that ended well is not failed.
#   4. Each script records its kind only at its end: after its last die, just before its done or PASS
#      line, so a run that fails records nothing.
# Usage: .github/hosts-check/tests/test_backup_metrics.sh   (promtool on PATH is used when present)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
files=$root/hosts/ansible/roles/k8s_backup/files
w=$(mktemp -d); trap 'chmod -R u+w "$w"; rm -rf "$w"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

# shellcheck source=/dev/null
lib() { (set -euo pipefail; . "$files/c1-backup-lib.sh"; "$@"); }

mkdir -p "$w/tf"
before=$(date +%s)
out=$(BACKUP_METRICS_DIR=$w/tf lib backup_mark_success volumes 2>&1); rc=$?
f=$w/tf/c1-backup-volumes.prom
if [[ $rc -eq 0 && -f $f ]] && grep -Eq '^c1_backup_last_success_timestamp_seconds\{kind="volumes"\} [0-9]+$' "$f" \
   && [[ $(stat -c %a "$f") == 644 ]] && [[ $(find "$w/tf" -mindepth 1 | wc -l) -eq 1 ]]; then
  t=$(awk '/^c1_backup/ {print $2}' "$f")
  if (( t >= before && t <= $(date +%s) )); then ok "writes c1-backup-volumes.prom, 0644, with the run's time and no temporary file"
  else bad "the time $t is not the run's time"; fi
else bad "backup_mark_success did not write the file as expected (rc $rc): $out"; ls -la "$w/tf"; cat "$f" 2>/dev/null; fi
if command -v promtool >/dev/null; then
  if promtool check metrics < "$f" >"$w/pt.txt" 2>&1; then ok "promtool check metrics accepts the file"
  else bad "promtool rejects the file: $(cat "$w/pt.txt")"; fi
fi

out=$(lib backup_mark_success etcd 2>&1); rc=$?
if [[ $rc -eq 0 && -z $out && ! -e $w/tf/c1-backup-etcd.prom ]]; then ok "without BACKUP_METRICS_DIR: nothing written, returns 0"
else bad "without BACKUP_METRICS_DIR it did something (rc $rc): $out"; fi

mkdir -p "$w/ro"; chmod 0555 "$w/ro"
out=$(BACKUP_METRICS_DIR=$w/ro lib backup_mark_success etcd 2>&1); rc=$?
if [[ $(id -u) -eq 0 ]]; then ok "skipped the unwritable-folder case: root writes anyway"
elif [[ $rc -eq 0 ]] && grep -q "could not write" <<<"$out" && [[ -z $(find "$w/ro" -mindepth 1) ]]; then ok "an unwritable folder is logged and returns 0"
else bad "an unwritable folder failed the run or left a file (rc $rc): $out"; fi

# 4. Where each script records its kind.
check_order() { # script kind end-pattern
  local s=$files/$1 mark last_die end
  mark=$(grep -n "^backup_mark_success $2\$" "$s" | cut -d: -f1)
  last_die=$(grep -n 'die ' "$s" | grep -v '^[0-9]*:#' | tail -1 | cut -d: -f1)
  end=$(grep -n "$3" "$s" | tail -1 | cut -d: -f1)
  if [[ -n $mark && $(grep -c "^backup_mark_success " "$s") -eq 1 && $mark -gt ${last_die:-0} && $((mark + 1)) -eq $end ]]; then
    ok "$1 records $2 after its last die, just before its end line"
  else bad "$1: backup_mark_success $2 at line ${mark:-none}, last die ${last_die:-none}, end line ${end:-none}"; fi
}
check_order c1-backup-volumes.sh volumes 'log "volume backup done"'
check_order c1-backup-etcd.sh etcd 'log "etcd backup done"'
check_order c1-restore-test-volumes.sh restore-test-volumes 'log "PASS: volume restore test'
check_order c1-restore-test-etcd.sh restore-test-etcd 'log "PASS: etcd restore test'

[[ $fail -eq 0 ]] && echo "backup metrics: all tests passed" || echo "backup metrics: a test failed"
exit "$fail"
