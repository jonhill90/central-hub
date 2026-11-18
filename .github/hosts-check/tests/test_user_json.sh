#!/usr/bin/env bash
# roles/k8s_identity/files/user-json.py on a small rendered realm (fake values):
#   1. One user comes out as JSON with its password and TOTP seed filled from the environment, groups kept.
#   2. A placeholder with no environment variable is an error, and prints no value.
#   3. A user that is not in the realm, and one that is in it twice, are errors.
#   4. A value with a quote or backslash stays valid JSON.
# Usage: .github/hosts-check/tests/test_user_json.sh   (needs python3 with PyYAML)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
tool=$root/hosts/ansible/roles/k8s_identity/files/user-json.py
cat > "$t/realm.yaml" <<'YAML'
spec:
  realm:
    users:
      - username: sign-in.test
        groups: [/lab-admins]
        credentials:
          - {type: password, value: "${PASSWORD_SIGN_IN_TEST}", temporary: false}
          - type: otp
            secretData: '{"value":"${TOTP_SIGN_IN_TEST}"}'
      - username: viewer
        groups: [/lab-viewers]
        credentials:
          - {type: password, value: "${PASSWORD_VIEWER}", temporary: false}
      - username: viewer
        groups: []
YAML
out=$(PASSWORD_SIGN_IN_TEST='pw"with\quote' TOTP_SIGN_IN_TEST=ABCDEFGH python3 -I "$tool" "$t/realm.yaml" sign-in.test)
python3 -I - "$out" <<'PY' && ok "1+4. the user's JSON has its password and seed filled, and stays valid JSON" || bad "1+4. $out"
import json, sys
u = json.loads(sys.argv[1])
assert u["username"] == "sign-in.test" and u["groups"] == ["/lab-admins"]
assert u["credentials"][0]["value"] == 'pw"with\\quote'
assert json.loads(u["credentials"][1]["secretData"])["value"] == "ABCDEFGH"
PY
if err=$(TOTP_SIGN_IN_TEST=ABCDEFGH python3 -I "$tool" "$t/realm.yaml" sign-in.test 2>&1 >/dev/null); then bad "2. a missing password was accepted"
elif grep -q 'PASSWORD_SIGN_IN_TEST}, which is not in the environment' <<< "$err" && ! grep -q ABCDEFGH <<< "$err"; then ok "2. a placeholder with no variable is an error and prints no value"
else bad "2. $err"; fi
if python3 -I "$tool" "$t/realm.yaml" nobody >/dev/null 2>&1; then bad "3a. a missing user was accepted"; else ok "3a. a user that is not in the realm is an error"; fi
if PASSWORD_VIEWER=x python3 -I "$tool" "$t/realm.yaml" viewer >/dev/null 2>&1; then bad "3b. a user defined twice was accepted"; else ok "3b. a user defined twice is an error"; fi
exit "$fail"
