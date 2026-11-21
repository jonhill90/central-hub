#!/usr/bin/env bash
# hosts/rebuild-k8s.sh `certs` and `gateway` stages, run_stage from a copy with `ap` and `wait_apps` stubbed (prod run 6, 2026-11-21):
#   1. With CERTS_SMOKE_LATE=true (the prod wrapper) `certs` runs k8s-certs.yml with --skip-tags smoke and nothing else.
#   2. With it, `gateway` runs k8s-gateway.yml, then k8s-certs.yml --tags smoke, then waits for every app, in that order.
#   3. Without it (dev, other envs) `certs` runs k8s-certs.yml whole and `gateway` runs the gateway play only, no smoke, no wait.
# Usage: .github/hosts-check/tests/test_rebuild_certs_order.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
sed -n '/^run_stage() {/,/^}/p' hosts/rebuild-k8s.sh > "$t/fn.sh"
[ -s "$t/fn.sh" ] || { echo "FAIL: run_stage not found"; exit 1; }
run() { # <env> <stage> [CERTS_SMOKE_LATE value]
  ENV_NAME=$1 CERTS_SMOKE_LATE=${3:-} bash -c '
    ap() { echo "AP $*"; }
    wait_apps() { echo "WAIT_APPS"; }
    kc() { return 1; }
    l2_report() { echo "L2"; }
    . "$1"; set +e; run_stage "$2"; echo "rc=$?"' _ "$t/fn.sh" "$2" 2>&1; }
out=$(run prod certs true)
[[ $out == *"AP playbooks/k8s-certs.yml --skip-tags smoke"* && $out == *"rc=0" && $(grep -c '^AP' <<< "$out") -eq 1 ]] && ok "1. prod certs skips the smoke test" || bad "1. $out"
out=$(run prod gateway true)
want=$'AP playbooks/k8s-gateway.yml\nAP playbooks/k8s-certs.yml --tags smoke\nWAIT_APPS\nrc=0'
[[ $out == "$want" ]] && ok "2. prod gateway: the gateway play, then the certs smoke test, then the wait for every app" || bad "2. $out"
out=$(run staging certs)
[[ $out == *"AP playbooks/k8s-certs.yml"* && $out != *"--skip-tags"* ]] && ok "3a. without the switch certs runs whole" || bad "3a. $out"
out=$(run staging gateway)
[[ $out == *"AP playbooks/k8s-gateway.yml"* && $out != *"--tags smoke"* && $out != *WAIT_APPS* ]] && ok "3b. without the switch gateway runs the gateway play only" || bad "3b. $out"
exit $fail
