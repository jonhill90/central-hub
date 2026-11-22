#!/usr/bin/env bash
# hosts/rebuild-k8s.sh argocd_signin_listed, with `kc` stubbed: prod's `ui` stage and `checks` ask Argo CD's argocd-cm whether it lists the
# provider `Lab sign-in`, so a missing oidc.config shows at once (prod resume 4, 2026-11-22: the probe said it was missing; cause then
# found to be a stale tick, but nothing in the run looked).
#   1. oidc.config naming Lab sign-in: passes.   2. no oidc.config: fails with the reason.   3. another provider name: fails.
#   4. the ui stage asks on prod only and after the playbook; a failing playbook is not asked.
# Usage: .github/hosts-check/tests/test_rebuild_argocd_signin.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
sed -n '/^argocd_signin_listed() {/,/^}/p' hosts/rebuild-k8s.sh > "$t/fn.sh"
[ -s "$t/fn.sh" ] || { echo "FAIL: argocd_signin_listed not found"; exit 1; }
run() { # <configmap json>
  printf '%s' "$1" > "$t/cm.json"
  T=$t bash -c 'kc() { echo "kc $*" >> "$T/calls"; cat "$T/cm.json"; }; . "$T/fn.sh"; argocd_signin_listed; echo "rc=$?"' > "$t/out" 2>&1
  out=$(cat "$t/out"); calls=$(cat "$t/calls" 2>/dev/null); rm -f "$t/calls"; }
run '{"data":{"oidc.config":"name: Lab sign-in\nissuer: https://sso.invalid\n"}}'
[[ $out == *"lists the Lab sign-in provider"* && $out == *"rc=0" && $calls == "kc -n argocd get configmap argocd-cm -o json" ]] && ok "1. oidc.config naming Lab sign-in passes, one read of one ConfigMap" || bad "1. $out | $calls"
run '{"data":{"url":"https://argocd.invalid"}}'
[[ $out == *"no oidc.config naming Lab sign-in"* && $out == *"rc=1" ]] && ok "2. no oidc.config fails" || bad "2. $out"
run '{"data":{"oidc.config":"name: Other\n"}}'
[[ $out == *"rc=1" ]] && ok "3. another provider name fails" || bad "3. $out"
# 4: the ui stage line
line=$(grep -n '^    ui) ap playbooks/k8s-gitops.yml --tags ui,sso' hosts/rebuild-k8s.sh | head -n1)
[[ $line == *'[ "$ENV_NAME" != prod ] || argocd_signin_listed'* && $line == *"--tags ui,sso &&"* ]] && ok "4. the ui stage asks after the playbook, and only on prod" || bad "4. $line"
grep -q 'if \[ "\$ENV_NAME" = prod \]; then argocd_signin_listed' hosts/rebuild-k8s.sh && ok "5. checks asks again on prod" || bad "5. checks does not ask"
exit $fail
