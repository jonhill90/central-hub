#!/usr/bin/env bash
# The owner's sign-in set-up (hosts/ansible/roles/agent_box/files/secrets-store-owner.sh), with a stub curl that
# records every call and body (no real store):
#   1. owner writes policy `owner` that holds kv/data/owner/* and kv/metadata/owner/* and nothing else, enables the
#      login `oidc` when it is missing, configures it with the issuer, client `openbao` and the store CA, and writes
#      role `owner` bound to the owner's user name, with the one redirect URI of the store's page and 15-minute tokens.
#   2. test does the same for role and policy `login-test` on kv/login-test/*, bound to the test user.
#   3. remove-test deletes the role, the policy and the probe, and writes nothing else.
#   4. The client secret and both AppRole IDs are in no curl argument and not in the output.
#   5. A refused admin login stops before any other call and says the HTTP code; settings that are not an https issuer
#      or a store name are refused before any call.
# Usage: .github/hosts-check/tests/test_secrets_store_owner.sh   (needs python3)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
root=$PWD
helper=$root/hosts/ansible/roles/agent_box/files/secrets-store-owner.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/bin" "$t/keys" "$t/log"
printf 'ROLEID0123456789abcdef' > "$t/keys/openbao-admin-role-id"
printf 'SECRETID0123456789abcdef' > "$t/keys/openbao-admin-secret-id"
printf 'GRAFANA_CLIENT_SECRET=g\nOPENBAO_CLIENT_SECRET=CLIENTSECRET0123456789\n' > "$t/keys/identity.env"
printf 'CA-PEM-TEXT' > "$t/ca.crt"
cat > "$t/settings.json" <<'J'
{"owner_login": {"issuer": "https://id.example.test/realms/lab", "host": "openbao.example.test", "username": "owner.name"}}
J
cat > "$t/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Records argv, and the body of --data / --data-binary @file; answers by URL.
out='' want_code=0 body='' url=''
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case ${args[i]} in
    -o) out=${args[i+1]} ;;
    -w) want_code=1 ;;
    --data-binary | --data) body=${args[i+1]} ;;
    http*) url=${args[i]} ;;
  esac
done
echo "$*" >> "$STUB_LOG/args"
[[ -n $body ]] || true
if [[ $body == @- ]]; then cat > "$STUB_LOG/stdin.last"; elif [[ $body == @* ]]; then cp "${body#@}" "$STUB_LOG/body.$(echo "$url" | sed 's#.*/v1/##; s#/#_#g')"; fi
echo "$url" >> "$STUB_LOG/urls"
code=200
[[ $(echo "$*" | grep -c -- '-X DELETE') -eq 0 ]] || code=${STUB_DELETE_CODE:-204}
reply='{}'
case $url in
  */auth/approle/login) code=${STUB_LOGIN_CODE:-200}; reply='{"auth":{"client_token":"TOKEN0123456789"}}' ;;
  */sys/auth) reply='{"data":{"token/":{},"oidc/":{}}}'; [[ -z ${STUB_NO_OIDC:-} ]] || reply='{"data":{"token/":{}}}' ;;
esac
[[ -z $out ]] || echo "$reply" > "$out"
((want_code)) && printf '%s' "$code"
[[ -n $out ]] || echo "$reply"
exit 0
STUB
chmod +x "$t/bin/curl"
export PATH="$t/bin:$PATH" STUB_LOG="$t/log"
run() { : > "$t/log/args"; : > "$t/log/urls"; rm -f "$t"/log/body.*; out=$(bash "$helper" "$1" https://openbao.example.test "$t/ca.crt" "$t/keys" "$t/settings.json" "$t" 2>&1); rc=$?; }

run owner
b=$t/log/body.sys_policies_acl_owner
if [[ $rc -eq 0 && -f $b ]] && python3 -I -c '
import json,sys
p=json.load(open(sys.argv[1]))["policy"]
paths=[l.split("\"")[1] for l in p.splitlines() if l.startswith("path")]
sys.exit(0 if paths==["kv/data/owner/*","kv/metadata/owner/*","kv/metadata/owner"] else 1)' "$b"; then
  ok "1a. owner: policy owner holds kv/owner/* and nothing else"
else bad "1a. rc=$rc $out"; fi
if python3 -I -c '
import json,sys
r=json.load(open(sys.argv[1])); c=json.load(open(sys.argv[2]))
ok = (r["bound_claims"]=={"preferred_username":["owner.name"]} and r["allowed_redirect_uris"]==["https://openbao.example.test/ui/vault/auth/oidc/oidc/callback"]
      and r["policies"]==["owner"] and r["token_ttl"]=="15m" and r["token_max_ttl"]=="15m" and r["role_type"]=="oidc"
      and c["oidc_discovery_url"]=="https://id.example.test/realms/lab" and c["oidc_client_id"]=="openbao"
      and c["oidc_client_secret"]=="CLIENTSECRET0123456789" and c["oidc_discovery_ca_pem"]=="CA-PEM-TEXT")
sys.exit(0 if ok else 1)' "$t/log/body.auth_oidc_role_owner" "$t/log/body.auth_oidc_config"; then
  ok "1b. owner: login config (issuer, client, CA) and role owner (user, redirect, 15 minutes)"
else bad "1b. role/config bodies differ"; fi
if ! grep -q 'sys/auth/oidc' "$t/log/urls"; then ok "1c. the login is not enabled again when it exists"; else bad "1c. enabled a second time"; fi

STUB_NO_OIDC=1 run owner
if [[ $rc -eq 0 ]] && grep -q 'sys/auth/oidc' "$t/log/urls" && [[ $(cat "$t/log/body.sys_auth_oidc") == *'"type":"oidc"'* ]]; then
  ok "1d. the login oidc is enabled when it is missing"
else bad "1d. rc=$rc"; fi

run test
if [[ $rc -eq 0 ]] && python3 -I -c '
import json,sys
p=json.load(open(sys.argv[1]))["policy"]; r=json.load(open(sys.argv[2]))
sys.exit(0 if "kv/data/login-test/*" in p and "owner" not in p and r["policies"]==["login-test"] and r["bound_claims"]=={"preferred_username":["signin-test"]} else 1)' \
  "$t/log/body.sys_policies_acl_login-test" "$t/log/body.auth_oidc_role_login-test"; then
  ok "2. test: role and policy login-test on kv/login-test/*, bound to the test user"
else bad "2. rc=$rc $out"; fi

run remove-test
if [[ $rc -eq 0 ]] && grep -q 'auth/oidc/role/login-test' "$t/log/urls" && grep -q 'sys/policies/acl/login-test' "$t/log/urls" &&
   grep -q 'kv/metadata/login-test/probe' "$t/log/urls" && ! grep -q 'sys/policies/acl/owner\|role/owner\|config' "$t/log/urls"; then
  ok "3. remove-test: deletes role, policy and probe, touches nothing else"
else bad "3. rc=$rc $(cat "$t/log/urls")"; fi

STUB_DELETE_CODE=403 run remove-test
if [[ $rc -ne 0 && $out == *"HTTP 403"* && $out != *PASS* ]]; then ok "3b. remove-test fails, with no PASS line, when a DELETE is refused"; else bad "3b. rc=$rc $out"; fi
STUB_DELETE_CODE=404 run remove-test
if [[ $rc -ne 0 ]]; then ok "3c. a 404 on the role or the policy fails; only the probe may be absent"; else bad "3c. rc=$rc"; fi

run owner
if [[ $out != *CLIENTSECRET* && $out != *SECRETID0123* && $out != *ROLEID0123* && $out != *TOKEN0123* ]] &&
   ! grep -q 'CLIENTSECRET\|SECRETID0123\|ROLEID0123\|TOKEN0123' "$t/log/args"; then
  ok "4. no secret, ID or token in any curl argument or in the output"
else bad "4. a secret leaked"; fi

STUB_LOGIN_CODE=403 run owner
if [[ $rc -ne 0 && $out == *"HTTP 403"* && $(grep -c . "$t/log/urls") -eq 1 ]]; then
  ok "5a. a refused admin login stops after the login call and names the HTTP code"
else bad "5a. rc=$rc $out"; fi
cp "$t/settings.json" "$t/settings.good"
echo '{"owner_login": {"issuer": "http://id.example.test/realms/lab", "host": "openbao.example.test", "username": "o"}}' > "$t/settings.json"
run owner
if [[ $rc -ne 0 && ! -s $t/log/urls ]]; then ok "5b. an http issuer is refused before any call"; else bad "5b. rc=$rc"; fi
exit $fail
