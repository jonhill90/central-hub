#!/usr/bin/env bash
# hosts/rebuild-k8s.sh settle_cronjob_jobs and prod_capture_diag, run from a copy with `kc` stubbed. A CronJob tick that lands while
# the cluster comes up leaves a failed Job and Error pods that the checks stage counts: dev run 10 (2026-11-21, the OpenBao
# snapshot) and prod resume 4 (2026-11-22, jellyfin-setup and panel-check). Source for the method: Kubernetes documents
# `kubectl create job --from=cronjob/<name>` as the way to run a CronJob's Job once by hand, and keeps failed Jobs and their pods
# until a history limit or a delete removes them (kubernetes.io docs, "CronJob" and "Jobs"; named here, not re-read this session).
#   1. No failed Job, or only Complete ones: nothing is run or deleted (Jobs read in all namespaces).
#   2. A failed Job with no newer Job: one Job is made from its CronJob in ITS namespace, waited for, then the failed Job and the
#      check Job go, each with --cascade=foreground.
#   3. The made Job does not complete: the function fails, prints that Job's last 30 log lines scrubbed (no password), and
#      deletes no failed Job.
#   4. A failed Job followed by a newer clean Complete Job of the same CronJob is settled: deleted, nothing made.
#   5. A Job that failed once and then succeeded (its first pod stays in Error) with nothing newer is rerun like case 2.
#   6. Two CronJobs in two namespaces (media and monitoring) are each handled in their own namespace.
#   7. A newer Job that itself failed does not settle an older failed one.
#   9. A failed Job of a suspended CronJob is deleted with no rerun;
#   8. prod_capture_diag reads with get only (applications, pods, events, why-not-ready), prefixes `diag:`, scrubs secrets, and
#      never fails; the failed-stage branch of the script calls it on prod.
# Usage: .github/hosts-check/tests/test_rebuild_cronjob_jobs.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
sed -n '/^settle_cronjob_jobs() {/,/^}/p' hosts/rebuild-k8s.sh > "$t/fn.sh"
[ -s "$t/fn.sh" ] || { echo "FAIL: settle_cronjob_jobs not found"; exit 1; }
job() { # <ns> <name> <cronjob> <failed> <succeeded> <created>
  printf '{"metadata":{"namespace":"%s","name":"%s","creationTimestamp":"%s","ownerReferences":[{"kind":"CronJob","name":"%s"}]},"status":{"failed":%s,"succeeded":%s}}' "$1" "$2" "$6" "$3" "$4" "$5"; }
run() { # <jobs json items> <wait rc>
  printf '{"items":[%s]}' "$1" > "$t/jobs.json"
  printf '{"items":[%s]}' "${CJ:-}" > "$t/cj.json"
  WAIT_RC=$2 T=$t SETTLE_POLL=0 repo=$PWD bash -c '
    kc() { echo "kc $*" >> "$T/calls"
      case "$*" in "get jobs -A -o json") cat "$T/jobs.json" ;;
        "get cronjobs -A -o json") cat "$T/cj.json" ;;
        *"--dry-run=client -o json"*) printf "{\"metadata\":{\"name\":\"x\",\"ownerReferences\":[{\"kind\":\"CronJob\",\"name\":\"c\"}]},\"spec\":{}}" ;;
        "-n "*" create -f -") cat > "$T/created.json" ;;
        *"get job/"*) if [ "$WAIT_RC" = 0 ]; then echo "1/"; else echo "/1"; fi ;;
        *" logs "*) echo "starting setup password=hunter2 failed to reach jellyfin" ;; esac; }
    . "$T/fn.sh"; settle_cronjob_jobs; echo "rc=$?"' > "$t/out" 2>&1
  out=$(cat "$t/out"); calls=$(cat "$t/calls" 2>/dev/null); rm -f "$t/calls"; }
read_only=$'kc get cronjobs -A -o json\nkc get jobs -A -o json'

run "$(job media a-1 jellyfin-setup 0 1 2026-11-22T01:00:00Z),$(job monitoring b-1 panel-check 0 1 2026-11-22T01:10:00Z)" 0
[[ $out == "rc=0" && $calls == "$read_only" ]] && ok "1. only Complete Jobs: nothing run or deleted" || bad "1. $out | $calls"

run "$(job media jellyfin-setup-1 jellyfin-setup 2 0 2026-11-22T01:00:00Z)" 0
want=$'kc get cronjobs -A -o json\nkc get jobs -A -o json\nkc -n media delete job jellyfin-setup-rebuild-check --ignore-not-found --cascade=foreground\nkc -n media create job jellyfin-setup-rebuild-check --from=cronjob/jellyfin-setup --dry-run=client -o json\nkc -n media create -f -\nkc -n media get job/jellyfin-setup-rebuild-check -o jsonpath={.status.succeeded}/{.status.failed}\nkc -n media delete job jellyfin-setup-1 --cascade=foreground\nkc -n media delete job jellyfin-setup-rebuild-check --cascade=foreground'
[[ $out == *"rc=0" && $calls == "$want" ]] && ok "2. a failed Job: one Job from its CronJob in its namespace, waited for, then the failed Job and the check Job go (foreground)" || bad "2. $out | $calls"
# 2b: the check Job is created with no owner, so the CronJob's history limit can't delete it, and its read does not wait out a fast failure.
run "$(job media jellyfin-setup-1 jellyfin-setup 2 0 2026-11-22T01:00:00Z)" 0
[[ $(cat "$t/created.json") != *ownerReferences* && $(cat "$t/created.json") == *'"name": "x"'* || $(cat "$t/created.json") == *'"name":"x"'* ]] &&
  ok "2b. the Job it creates has no ownerReferences (the CronJob's history limit can't delete it)" || bad "2b. $(cat "$t/created.json")"

run "$(job media jellyfin-setup-1 jellyfin-setup 2 0 2026-11-22T01:00:00Z)" 1
[[ $out == *"does not complete with the cluster up; last 30 log lines"* && $out == *"failed to reach jellyfin"* && $out != *"hunter2"* &&
   $out == *"rc=1" && $calls == *"logs job/jellyfin-setup-rebuild-check --tail=30"* && $calls != *"delete job jellyfin-setup-1"* ]] &&
  ok "3. a Job that does not complete fails with its last 30 log lines scrubbed and keeps the failed Job" || bad "3. $out | $calls"

run "$(job monitoring panel-check-1 panel-check 1 0 2026-11-22T01:00:00Z),$(job monitoring panel-check-2 panel-check 0 1 2026-11-22T01:10:00Z)" 0
[[ $out == *"rc=0" && $calls == $'kc get cronjobs -A -o json\nkc get jobs -A -o json\nkc -n monitoring delete job panel-check-1 --cascade=foreground' ]] &&
  ok "4. a failed Job with a newer clean Job: deleted, nothing made" || bad "4. $out | $calls"

run "$(job openbao openbao-snapshot-2 openbao-snapshot 1 1 2026-11-22T01:00:00Z)" 0
[[ $out == *"rc=0" && $calls == *"create job openbao-snapshot-rebuild-check --from=cronjob/openbao-snapshot"* && $calls == *"delete job openbao-snapshot-2 --cascade=foreground"* ]] &&
  ok "5. a Job that failed once and then succeeded, nothing newer: rerun" || bad "5. $out | $calls"

run "$(job media jf-1 jellyfin-setup 2 0 2026-11-22T01:00:00Z),$(job monitoring pc-1 panel-check 1 0 2026-11-22T01:05:00Z)" 0
[[ $out == *"rc=0" && $calls == *"-n media create job jellyfin-setup-rebuild-check"* && $calls == *"-n monitoring create job panel-check-rebuild-check"* &&
   $calls == *"-n media delete job jf-1 "* && $calls == *"-n monitoring delete job pc-1 "* ]] &&
  ok "6. two CronJobs in two namespaces: each rerun and cleaned in its own" || bad "6. $out | $calls"

run "$(job media jf-1 jellyfin-setup 2 0 2026-11-22T01:00:00Z),$(job media jf-2 jellyfin-setup 3 0 2026-11-22T01:10:00Z)" 0
[[ $out == *"rc=0" && $calls == *"create job jellyfin-setup-rebuild-check"* && $calls == *"delete job jf-1 "* && $calls == *"delete job jf-2 "* ]] &&
  ok "7. a newer Job that failed settles nothing: both failed Jobs wait for the rerun" || bad "7. $out | $calls"


# 9: a failed Job of a suspended CronJob (the render's way of saying "off") is deleted with no rerun; an active CronJob's is rerun.
cjob() { printf '{"metadata":{"namespace":"%s","name":"%s"},"spec":{"suspend":%s}}' "$1" "$2" "$3"; }
CJ="$(cjob media jellyfin-setup true)" run "$(job media jf-1 jellyfin-setup 2 0 2026-11-22T01:00:00Z),$(job media jf-2 jellyfin-setup 3 0 2026-11-22T01:10:00Z)" 0
[[ $out == *"rc=0" && $out == *"which is suspended"* && $calls == *"-n media delete job jf-1 --cascade=foreground"* && $calls == *"-n media delete job jf-2 --cascade=foreground"* &&
   $calls != *create* && $calls != *wait* ]] &&
  ok "9. a suspended CronJob's failed Jobs are deleted, nothing is made or waited for" || bad "9. $out | $calls"
CJ="$(cjob media jellyfin-setup false),$(cjob monitoring panel-check true)" run "$(job media jf-1 jellyfin-setup 2 0 2026-11-22T01:00:00Z),$(job monitoring pc-1 panel-check 1 0 2026-11-22T01:05:00Z)" 0
[[ $out == *"rc=0" && $calls == *"-n media create job jellyfin-setup-rebuild-check"* && $calls != *"-n monitoring create"* && $calls == *"-n monitoring delete job pc-1 --cascade=foreground"* ]] &&
  ok "9b. with one active and one suspended CronJob: the active one is rerun, the suspended one's Job is only deleted" || bad "9b. $out | $calls"

# 8
sed -n '/^diag_why_not_ready() {/,/^}/p;/^prod_capture_diag() {/,/^}/p' hosts/rebuild-k8s.sh > "$t/diag.sh"
[ "$(grep -c '^diag_why_not_ready\|^prod_capture_diag' "$t/diag.sh")" = 2 ] || { bad "8. diag functions not found"; exit 1; }
: > "$t/calls8"
out8=$(T=$t repo=$PWD log=$t/log raw=$t/raw bash -c '
  kc() { echo "kc $*" >> "$T/calls8"
    case "$*" in
      "get pods -A --no-headers") printf "media jellyfin-setup-1-x 0/1 Error 0 10m\nmonitoring ok-1 1/1 Running 0 1h\n" ;;
      "-n media logs jellyfin-setup-1-x --tail=30 --all-containers=true") echo "login password=hunter2 refused" ;;
      "-n argocd get applications.argoproj.io -o json") echo "{\"items\":[]}" ;;
    esac; }
  : > "$log"; : > "$raw"
  . "$T/diag.sh"; prod_capture_diag; echo "rc=$?"' 2>&1)
calls8=$(cat "$t/calls8")
writes=$(grep -cE ' (apply|delete|create|patch|annotate|edit|replace|exec|cp) |get secret' "$t/calls8" || true)
lg=$(cat "$t/log")
if [[ $out8 == *"diag: the run failed, so prod's cluster is read"* && $out8 == *"rc=0" && $lg == *"diag: == pods not Running or Completed"* &&
      $lg == *"diag: media jellyfin-setup-1-x 0/1 Error"* && $lg == *"diag: login password=<redacted> refused"* && $lg != *"hunter2"* &&
      $(cat "$t/raw") == *"diag: login password=<redacted> refused"* && $writes -eq 0 ]] &&
   grep -q 'if \[ "\$ENV_NAME" = prod \]; then prod_capture_diag' hosts/rebuild-k8s.sh; then
  ok "8. prod_capture_diag: get and logs only, diag: lines in the log, secrets scrubbed, never fails; the failed-stage branch calls it on prod"
else bad "8. $out8 | writes=$writes | $calls8"; fi

# 8b: the diag keeps every line it prints: six pods in Error with 30 log lines each, and 25 events, are about 230 lines, and a cap of 200 cut the
# last pod's end, where a panel-check Job's failing lines are (prod resume 6, 2026-11-22: the diag showed only the panels with data).
: > "$t/calls8"
T=$t repo=$PWD log=$t/log8 raw=$t/raw8 bash -c '
  kc() { echo "kc $*" >> "$T/calls8"
    case "$*" in
      "get pods -A --no-headers") for n in 1 2 3 4 5 6; do echo "monitoring pc-$n 0/1 Error 0 10m"; done ;;
      "get events -A --sort-by=.lastTimestamp --no-headers") for n in $(seq 1 30); do echo "ns ev-$n Normal x y"; done ;;
      *" logs "*) for n in $(seq 1 29); do echo "panel line $n: 1"; done; echo "Hours since the last volume backup: no data" ;;
      "-n argocd get applications.argoproj.io -o json") echo "{\"items\":[]}" ;;
    esac; }
  : > "$log"; : > "$raw"
  . "$T/diag.sh"; prod_capture_diag' > /dev/null 2>&1
if [ "$(grep -c "volume backup: no data" "$t/log8")" -eq 6 ]; then ok "8b. the diag keeps the last line of all six pods' logs (about 230 lines, no cap at 200)"
else bad "8b. $(grep -c "volume backup: no data" "$t/log8") of 6 pods' last lines kept, $(wc -l < "$t/log8") lines"; fi
exit $fail
