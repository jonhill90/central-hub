#!/usr/bin/env bash
# hosts/rebuild-k8s.sh settle_snapshot_jobs, run from a copy with `kc` stubbed (dev run 10, 2026-11-21): a snapshot CronJob tick at
# minute 17 that lands while the store comes up leaves a failed Job and Error pods that the checks stage counts.
#   1. No failed snapshot Job: nothing is run or deleted.
#   2. A failed snapshot Job (never succeeded) and the check Job completes: the check Job is made from the CronJob, waited for, and the
#      failed Job and the check Job are deleted.
#   3. The check Job does not complete: the function fails and deletes no failed Job.
#   4. A failed Job of another CronJob is left alone and nothing is run.
#   5. A snapshot Job that failed once and then succeeded (backoffLimit 1: its first pod stays in Error) is settled like case 2.
# Usage: .github/hosts-check/tests/test_rebuild_snapshot_jobs.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
sed -n '/^settle_snapshot_jobs() {/,/^}/p' hosts/rebuild-k8s.sh > "$t/fn.sh"
[ -s "$t/fn.sh" ] || { echo "FAIL: settle_snapshot_jobs not found"; exit 1; }
job() { # <name> <cronjob> <failed> <succeeded>
  printf '{"metadata":{"name":"%s","ownerReferences":[{"kind":"CronJob","name":"%s"}]},"status":{"failed":%s,"succeeded":%s}}' "$1" "$2" "$3" "$4"; }
run() { # <jobs json items> <wait rc>
  printf '{"items":[%s]}' "$1" > "$t/jobs.json"
  WAIT_RC=$2 T=$t bash -c '
    kc() { echo "kc $*" >> "$T/calls"
      case "$*" in "-n openbao get jobs -o json") cat "$T/jobs.json" ;; *"wait "*) return "$WAIT_RC" ;; esac; }
    . "$T/fn.sh"; settle_snapshot_jobs; echo "rc=$?"' > "$t/out" 2>&1
  out=$(cat "$t/out"); calls=$(cat "$t/calls" 2>/dev/null); rm -f "$t/calls"; }
run "$(job openbao-snapshot-1 openbao-snapshot 0 1)" 0
[[ $out == "rc=0" && $calls == "kc -n openbao get jobs -o json" ]] && ok "1. only a good snapshot Job: nothing run or deleted" || bad "1. $out | $calls"
run "$(job openbao-snapshot-1 openbao-snapshot 2 0)" 0
want=$'kc -n openbao get jobs -o json\nkc -n openbao delete job openbao-snapshot-rebuild-check --ignore-not-found --cascade=foreground\nkc -n openbao create job openbao-snapshot-rebuild-check --from=cronjob/openbao-snapshot\nkc -n openbao wait --for=condition=complete job/openbao-snapshot-rebuild-check --timeout=300s\nkc -n openbao delete job openbao-snapshot-1 --cascade=foreground\nkc -n openbao delete job openbao-snapshot-rebuild-check --cascade=foreground'
[[ $out == *"rc=0" && $calls == "$want" ]] && ok "2. a failed snapshot Job: the Job is run once from the CronJob, waited for, then the failed Job and the check Job go, each with --cascade=foreground so their pods are gone before the pod check" || bad "2. $out | $calls"
run "$(job openbao-snapshot-1 openbao-snapshot 2 0)" 1
[[ $out == *"the snapshot Job does not complete with the store up"* && $out == *"rc=1" && $calls != *"delete job openbao-snapshot-1"* ]] && ok "3. a check Job that does not complete fails and keeps the failed Job" || bad "3. $out | $calls"
run "$(job other-1 other 3 0)" 0
[[ $out == "rc=0" && $calls == "kc -n openbao get jobs -o json" ]] && ok "4. another CronJob's failed Job is left alone" || bad "4. $out | $calls"
run "$(job openbao-snapshot-2 openbao-snapshot 1 1)" 0
[[ $out == *"rc=0" && $calls == *"create job openbao-snapshot-rebuild-check"* && $calls == *"delete job openbao-snapshot-2 --cascade=foreground"* ]] && ok "5. a snapshot Job that failed once and then succeeded is settled too" || bad "5. $out | $calls"
exit $fail
