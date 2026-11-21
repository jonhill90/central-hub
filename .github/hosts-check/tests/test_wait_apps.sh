#!/usr/bin/env bash
# hosts/rebuild-k8s.sh wait_apps, run for real with a stand-in `kc` that prints an Argo CD application table:
#   1. Every app Synced and Healthy: returns 0.
#   2. gateway Degraded and jellyfin OutOfSync (prod run 6, 2026-11-21): without a defer list the wait fails and names both; with
#      the list "gateway jellyfin" (the `apps` stage's APPS_DEFER on prod) it passes.
#   3. Another app not Healthy still fails with the defer list, and names only that app.
#   4. A defer name does not match a longer app name (jellyfin-extras is not jellyfin).
# Usage: .github/hosts-check/tests/test_wait_apps.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
sed -n '/^wait_apps() {/,/^}/p' hosts/rebuild-k8s.sh > "$t/fn.sh"
[ -s "$t/fn.sh" ] || { echo "FAIL: wait_apps not found"; exit 1; }
table() { printf '%s\n' "$@" > "$t/apps"; }
run() { # [defer list]
  ( kc() { cat "$t/apps"; }; sleep() { :; }; export APPS_TIMEOUT=0; . "$t/fn.sh"; wait_apps "$@" ) 2>&1; }
table "root Synced Healthy" "argocd Synced Healthy" "gateway Synced Healthy"
out=$(run); rc=$?; [[ $rc -eq 0 ]] && ok "1. all Synced and Healthy returns 0" || bad "1. $rc $out"
table "root Synced Healthy" "gateway Synced Degraded" "jellyfin OutOfSync Progressing" "cert-manager Synced Healthy"
out=$(run); rc=$?
[[ $rc -ne 0 && $out == *"gateway "*"Degraded"* && $out == *"jellyfin "*"Progressing"* ]] && ok "2a. without a defer list both bad apps fail the wait and are named" || bad "2a. $rc $out"
out=$(run "gateway jellyfin"); rc=$?; [[ $rc -eq 0 ]] && ok "2b. with the defer list gateway and jellyfin do not hold the wait" || bad "2b. $rc $out"
table "root Synced Healthy" "gateway Synced Degraded" "grafana Synced Progressing"
out=$(run "gateway jellyfin"); rc=$?
[[ $rc -ne 0 && $out == *grafana* && $out != *"gateway "* ]] && ok "3. another unhealthy app still fails the wait; the deferred one is not named" || bad "3. $rc $out"
table "root Synced Healthy" "jellyfin-extras Synced Degraded"
out=$(run "gateway jellyfin"); rc=$?
[[ $rc -ne 0 && $out == *jellyfin-extras* ]] && ok "4. a defer name matches whole app names only" || bad "4. $rc $out"
exit $fail
