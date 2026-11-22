#!/usr/bin/env bash
# The SSH certificate set-up (hosts/ansible/roles/agent_box/files/secrets-store-ssh.sh, D-0064), with a stub curl that
# records every call and body (no real store):
#   1. apply mounts ssh-user and ssh-host, makes each CA key only when GET config/ca finds none, writes role admin
#      (one principal, 1h, permit-pty), role hosts, policy ssh-sign (one path) and login role ssh-admin (group, redirect, 15m).
#   2. apply never writes config/ca when the CA exists (a second write would replace the key).
#   3. no AppRole ID appears in an argument; a refused admin login stops before any write.
#   4. sign-host sends a host-type request for the given names; names with a space are refused before signing.
# Usage: .github/hosts-check/tests/test_secrets_store_ssh.sh   (needs python3)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
root=$PWD
helper=$root/hosts/ansible/roles/agent_box/files/secrets-store-ssh.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
mkdir -p "$t/bin" "$t/keys" "$t/log"
printf 'ROLEID0123456789abcdef' > "$t/keys/openbao-admin-role-id"
printf 'SECRETID0123456789abcdef' > "$t/keys/openbao-admin-secret-id"
printf 'CA-PEM-TEXT' > "$t/ca.crt"
printf 'ssh-ed25519 AAAAHOSTKEY host\n' > "$t/host.pub"
echo '{"ssh_ca": {"zone": "example.test", "issuer": "https://id.example.test/realms/lab"}}' > "$t/settings.json"
cat > "$t/bin/curl" <<'STUB'
#!/usr/bin/env bash
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
if [[ $body == @- ]]; then cat > "$STUB_LOG/stdin.last"; elif [[ $body == @* ]]; then cp "${body#@}" "$STUB_LOG/body.$(echo "$url" | sed 's#.*/v1/##; s#/#_#g')"; fi
echo "$url" >> "$STUB_LOG/urls"
code=200; reply='{}'
case $url in
  */auth/approle/login) code=${STUB_LOGIN_CODE:-200}; reply='{"auth":{"client_token":"TOKEN0123456789"}}' ;;
  */sys/mounts) reply='{"data":{"cubbyhole/":{}}}'; [[ -z ${STUB_HAVE_MOUNTS:-} ]] || reply='{"data":{"ssh-user/":{},"ssh-host/":{}}}' ;;
  */config/ca) [[ -z ${STUB_HAVE_CA:-} ]] || reply='{"data":{"public_key":"ssh-ed25519 AAAACA ca\n"}}' ;;
  */auth/oidc/config) reply='{"data":{}}' ;;
  */ssh-host/sign/hosts) reply='{"data":{"signed_key":"ssh-ed25519-cert-v01@openssh.com AAAACERT\n"}}' ;;
esac
[[ -z $out ]] || echo "$reply" > "$out"
((want_code)) && printf '%s' "$code"
[[ -n $out ]] || echo "$reply"
exit 0
STUB
chmod +x "$t/bin/curl"
export PATH="$t/bin:$PATH" STUB_LOG="$t/log"
run() { : > "$t/log/args"; : > "$t/log/urls"; rm -f "$t"/log/body.*; out=$(bash "$helper" "$@" 2>&1); rc=$?; }
base=(https://openbao.example.test "$t/ca.crt" "$t/keys" "$t/settings.json" "$t")

run apply "${base[@]}"
if [[ $rc -eq 0 ]] && python3 -I -c '
import json,sys
d=sys.argv[1]
def j(n): return json.load(open(d+"/body."+n))
r=j("ssh-user_roles_admin"); h=j("ssh-host_roles_hosts"); p=json.loads(json.dumps(j("sys_policies_acl_ssh-sign")))["policy"]; o=j("auth_oidc_role_ssh-admin")
ok=(r["allowed_users"]=="lab-admin" and r["allow_user_certificates"] is True and r["ttl"]=="1h" and r["max_ttl"]=="1h" and r["allowed_extensions"]=="permit-pty" and r["allow_user_key_ids"] is False
    and h["allow_host_certificates"] is True and h["allow_user_certificates"] is False and h["allowed_domains"]=="example.test"
    and [l for l in p.splitlines() if l.startswith("path")]==["path \"ssh-user/sign/admin\" { capabilities = [\"create\", \"update\"] }"]
    and o["bound_claims"]=={"groups":["lab-admins"]} and o["policies"]==["ssh-sign"] and o["token_ttl"]=="15m" and o["allowed_redirect_uris"]==["http://localhost:8250/oidc/callback"])
sys.exit(0 if ok else 1)' "$t/log"; then ok "1. apply writes both engines, roles, the one-path policy and the group-bound login role"; else bad "1. rc=$rc $out"; fi
if [[ -f $t/log/body.ssh-user_config_ca && -f $t/log/body.ssh-host_config_ca ]]; then ok "1b. each CA key is made when there is none"; else bad "1b. no CA made"; fi

STUB_HAVE_MOUNTS=1 STUB_HAVE_CA=1 run apply "${base[@]}"
if [[ $rc -eq 0 && ! -f $t/log/body.ssh-user_config_ca && ! -f $t/log/body.ssh-host_config_ca && $out == *"kept, never replaced"* ]]; then ok "2. an existing CA is never written again"; else bad "2. rc=$rc $out"; fi

if ! grep -q 'ROLEID0123456789abcdef\|SECRETID0123456789abcdef' "$t/log/args" && [[ $out != *SECRETID* && $out != *TOKEN0123* ]]; then ok "3. no ID or token in an argument or the output"; else bad "3. a secret leaked"; fi
STUB_LOGIN_CODE=403 run apply "${base[@]}"
if [[ $rc -ne 0 && $out == *"HTTP 403"* && $(grep -c 'sys/mounts\|roles' "$t/log/urls") -eq 0 ]]; then ok "3b. a refused admin login stops before any write"; else bad "3b. rc=$rc $out"; fi

run sign-host "${base[@]}" "$t/host.pub" box1.example.test "$t/host-cert.pub"
if [[ $rc -eq 0 ]] && grep -q 'cert-v01' "$t/host-cert.pub" && python3 -I -c '
import json,sys
b=json.load(open(sys.argv[1])); sys.exit(0 if b["cert_type"]=="host" and b["valid_principals"]=="box1.example.test" else 1)' "$t/log/body.ssh-host_sign_hosts"; then ok "4. sign-host asks for a host certificate for the given names"; else bad "4. rc=$rc $out"; fi
run sign-host "${base[@]}" "$t/host.pub" 'a b' "$t/x"
if [[ $rc -ne 0 ]] && ! grep -q "sign/hosts" "$t/log/urls"; then ok "4b. names with a space are refused before any signing call"; else bad "4b. rc=$rc $out"; fi
run plan "${base[@]}"
if [[ $rc -eq 0 && ! -s $t/log/urls && $out != *example.test* ]]; then ok "5. plan makes no call and prints no name"; else bad "5. rc=$rc $out"; fi
exit $fail
