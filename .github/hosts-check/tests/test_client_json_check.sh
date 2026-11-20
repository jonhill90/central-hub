#!/usr/bin/env bash
# client-json.py --check (hosts/ansible/roles/k8s_identity/files/client-json.py): the role runs it before the task that has no_log,
# so a failed apply shows why.
#   1. With the client in the realm and its secret in the environment: prints "client X: ok", rc 0, and no secret in the output.
#   2. With the client missing from the realm: rc 1 and "found 0" on stderr (measured on c1 on 2026-11-20: proxmox is absent
#      when no Proxmox web name is given, so the client is not rendered).
#   3. With the secret variable unset: rc 1 and the variable's name, not its value, on stderr.
#   4. Without --check the JSON still prints with the secret filled in (the old behaviour).
# Usage: .github/hosts-check/tests/test_client_json_check.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
script=hosts/ansible/roles/k8s_identity/files/client-json.py
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cat > "$t/realm.yaml" <<'Y'
spec:
  realm:
    clients:
      - clientId: demo
        secret: ${DEMO_CLIENT_SECRET}
Y
out=$(DEMO_CLIENT_SECRET=s3cret python3 -I "$script" "$t/realm.yaml" demo --check 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$out" = "client demo: ok" ] && ok "1 present: $out" || bad "1 rc=$rc out=$out"
out=$(DEMO_CLIENT_SECRET=s3cret python3 -I "$script" "$t/realm.yaml" missing --check 2>&1); rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q "found 0" && ok "2 missing: $out" || bad "2 rc=$rc out=$out"
out=$(env -u DEMO_CLIENT_SECRET python3 -I "$script" "$t/realm.yaml" demo --check 2>&1); rc=$?
[ "$rc" = 1 ] && echo "$out" | grep -q 'DEMO_CLIENT_SECRET' && ok "3 unset: $out" || bad "3 rc=$rc out=$out"
out=$(DEMO_CLIENT_SECRET=s3cret python3 -I "$script" "$t/realm.yaml" demo 2>&1); rc=$?
[ "$rc" = 0 ] && echo "$out" | grep -q s3cret && ok "4 without --check the JSON has the secret" || bad "4 rc=$rc out=$out"
exit $fail
