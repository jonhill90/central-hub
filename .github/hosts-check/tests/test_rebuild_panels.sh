#!/usr/bin/env bash
# hosts/rebuild-k8s.sh's last dev stage, `panels`: dev only; one Job from the suspended panel-check CronJob, its
# output, up{namespace="openbao"} and up{namespace="media"} through the API server, the store's StatefulSet age, and
# the snapshot note on a fresh store. It never fails the run, even under `set -e` with every read failing, and its
# `read:` lines reach the short log. Runs run_stage and panels_read from a copy with `kc` stubbed.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)
script=$src/hosts/rebuild-k8s.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
sed -n '/^PANELS_WAIT_STEPS=/p;/^PANELS_WAIT_S=/p;/^panels_read() {/,/^}/p;/^run_stage() {/,/^}/p' "$script" > "$t/fn.sh"
grep -q '^panels_read() {' "$t/fn.sh" || { echo "FAIL: panels_read not found"; exit 1; }

# A stand-in for kc: KC=ok|failed|pending|down picks the Job's end; every call is logged to $t/calls.
cat > "$t/kc.sh" <<'EOF'
kc() {
  echo "kc $*" >> "$CALLS"
  [ "$KC" != down ] || return 1
  case "$*" in
    "-n monitoring create job --from=cronjob/panel-check "*) echo "job.batch/x created" ;;
    "-n monitoring get job "*)
      case $KC in ok) echo "1/" ;; failed) echo "/1" ;; *) echo "/" ;; esac ;;
    "-n monitoring logs job/"*) printf '%s\n' "OpenBao unsealed: 1" "Hours since the last snapshot: no data" "panel check: some panels have no data" ;;
    "-n openbao get cronjob openbao-snapshot "*) echo "" ;;
    *"query=up%7Bnamespace%3D%22openbao%22%7D")
      echo '{"status":"success","data":{"result":[{"metric":{"job":"openbao","pod":"openbao-0"},"value":[1,"1"]}]}}' ;;
    *"query=up%7Bnamespace%3D%22media%22%7D") echo '{"status":"success","data":{"result":[]}}' ;;
    "-n openbao get statefulset openbao "*) echo "2026-11-18T22:00:00Z" ;;
    *) echo "unexpected: $*" >&2; return 1 ;;
  esac
}
EOF
run() { # env, then VAR=value pairs; prints the output and rc= last, the way the stage loop runs it (set -e subshell)
  local envname=$1; shift
  : > "$t/calls"
  env "$@" ENV_NAME="$envname" CALLS="$t/calls" stamp=20261118T224500Z bash -c '
    . "$1"; . "$2"
    set +e
    (set -e; run_stage panels); echo "rc=$?"' _ "$t/kc.sh" "$t/fn.sh"
}
check() { # name, output, must-contain, must-not-contain
  if [[ $2 == *"$3"* ]] && { [ -z "$4" ] || [[ $2 != *"$4"* ]]; }; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi
}

for envname in prod staging ""; do
  out=$(run "$envname" KC=ok OPENBAO_SEAL_KEY_FILE=/k)
  check "1. panels refuses ENV_NAME='$envname' before any read" "$out$(cat "$t/calls")" "rc=1" "kc "
done

out=$(run dev KC=ok OPENBAO_SEAL_KEY_FILE=/k PANELS_WAIT_S=0)
calls=$(cat "$t/calls")
check "2a. the Job is made from the panel-check CronJob, named for the run" "$calls" "kc -n monitoring create job --from=cronjob/panel-check panel-check-run-20261118t224500z" ""
check "2b. a Job that succeeded says so" "$out" "read: panel check panel-check-run-20261118t224500z ended, every panel has data" ""
check "2c. the panel check's own lines follow" "$out" "read: OpenBao unsealed: 1" ""
check "2d. a store with no snapshot yet gets the note" "$out" "read: no snapshot of this store has run yet" ""
check "2e. up for openbao, one line per series" "$out" 'read: up{namespace="openbao"}: job=openbao pod=openbao-0 up=1' ""
check "2f. up for media with no series says so" "$out" 'read: up{namespace="media"}: no series' ""
check "2g. the store's StatefulSet age" "$out" "read: StatefulSet openbao/openbao made 2026-11-18T22:00:00Z, " ""
check "2h. the stage passes" "$out" "rc=0" ""
writes=$(grep -Ec ' (create|delete|apply|patch|scale|edit|replace|label|annotate) ' "$t/calls" || true)
check "2i. nothing is written but the one Job (one create; no delete, apply, patch or scale)" "writes=$writes" "writes=1" ""

out=$(run dev KC=failed OPENBAO_SEAL_KEY_FILE=/k PANELS_WAIT_S=0)
check "3. a failed Job is named as such and the stage still passes" "$out" "ended with panels that have no data (the Job failed)" "rc=1"

out=$(run dev KC=pending OPENBAO_SEAL_KEY_FILE=/k PANELS_WAIT_STEPS=2 PANELS_WAIT_S=0)
check "4a. a Job with no end says how many reads it waited" "$out" "had no result after 2 reads" "rc=1"
check "4b. it reads the Job exactly that many times" "$(grep -c 'get job' "$t/calls")" "2" ""

out=$(run dev KC=down OPENBAO_SEAL_KEY_FILE=/k PANELS_WAIT_S=0)
check "5a. with every read failing the Job is named as not run" "$out" "read: panel check not run" ""
check "5b. Prometheus not answering is said per namespace" "$out" 'read: up{namespace="media"}: not read' ""
check "5c. the StatefulSet not read is said" "$out" "read: StatefulSet openbao/openbao: not read" ""
check "5d. and the stage still passes under set -e" "$out" "rc=0" ""

out=$(run dev KC=ok PANELS_WAIT_S=0)
check "6a. without the store's key file no snapshot note" "$out" "rc=0" "no snapshot of this store"
check "6b. and the StatefulSet is not looked for" "$out$(cat "$t/calls")" "the store is not in this cluster" "get statefulset"

# The read lines reach the short log; the stage's other output does not.
sed -n '/^  if \[ "\$s" = panels \]; then$/,/^  fi$/p' "$script" > "$t/short.sh"
if [ -s "$t/short.sh" ]; then
  printf '%s\n' '===== panels' 'read: OpenBao unsealed: 1' 'some other line' '===== next' 'read: not this stage' > "$t/raw"
  : > "$t/log"
  s=panels raw=$t/raw log=$t/log bash -c '. "$1"' _ "$t/short.sh"
  check "7. only the panels stage's read lines reach the short log" "$(cat "$t/log")" "  panels: read: OpenBao unsealed: 1" "other line"
  check "7b. not the next stage's" "$(cat "$t/log")" "panels" "not this stage"
else
  echo "FAIL 7. the panels short-log block is missing or changed"; fail=1
fi
exit $fail
