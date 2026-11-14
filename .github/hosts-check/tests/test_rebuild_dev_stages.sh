#!/usr/bin/env bash
# hosts/rebuild-k8s.sh's two dev-only stages, dev-ca and identity-keycloak: both refuse any ENV_NAME other
# than dev before they run Ansible, dev-ca stops with a clear message when the k8s_certs role has no devca
# tag, and a dev run appends both after the default stages. Runs run_stage from a copy with `ap` stubbed.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)
script=$src/hosts/rebuild-k8s.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
sed -n '/^run_stage() {/,/^}/p' "$script" > "$t/fn.sh"
[ -s "$t/fn.sh" ] || { echo "FAIL: run_stage not found"; exit 1; }

# run_stage <env> <stage> <repo>: prints the output, and the exit code on the last line.
run() {
  ENV_NAME=$1 repo=$3 bash -c '
    ap() { echo "AP $*"; }
    . "$1"
    set +e
    run_stage "$2"; echo "rc=$?"' _ "$t/fn.sh" "$2"
}
mkdir -p "$t/ok/hosts/ansible/roles/k8s_certs/tasks" "$t/bad/hosts/ansible/roles/k8s_certs/tasks"
echo "tags: [devca, never]" > "$t/ok/hosts/ansible/roles/k8s_certs/tasks/main.yml"
echo "tags: [issue]" > "$t/bad/hosts/ansible/roles/k8s_certs/tasks/main.yml"

check() { # name, output, must-contain, must-not-contain
  if [[ $2 == *"$3"* ]] && { [ -z "$4" ] || [[ $2 != *"$4"* ]]; }; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi
}
for stage in dev-ca identity-keycloak; do
  for envname in prod staging ""; do
    out=$(run "$envname" "$stage" "$t/ok")
    check "$stage refuses ENV_NAME='${envname}'" "$out" "rc=1" "AP "
    check "$stage says dev only for '${envname}'" "$out" "dev only" ""
  done
  out=$(run dev "$stage" "$t/ok")
  check "$stage runs on dev" "$out" "AP playbooks/" "rc=1"
done
out=$(run dev dev-ca "$t/bad")
check "dev-ca names the missing devca tag" "$out" "has no devca tag" "AP "
check "dev-ca fails without the tag" "$out" "rc=1" ""
# The dev identity stage never needs the owner's private theme folder: it passes an empty theme dir.
out=$(run dev identity-keycloak "$t/ok")
check "identity-keycloak runs with an empty theme dir" "$out" "k8s_identity_theme_dir= " ""
# The default list stays a default: dev appends the two stages only when no --only is given.
if grep -q 'ENV_NAME" = dev \] && \[ -z "\$only" \]; then stages="\$stages dev-ca identity-keycloak"' "$script"; then
  echo "ok   a dev run without --only appends dev-ca and identity-keycloak"
else echo "FAIL: the dev-only append line is missing or changed"; fail=1; fi
exit $fail
