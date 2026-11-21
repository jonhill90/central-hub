#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store-owner.sh: the owner's sign-in to the secrets store's web page, through
# Keycloak (OIDC), set up and proved from the box. Called by secrets-store.sh (never directly), as user `keys`, with:
#   secrets-store-owner.sh <action> <store address> <CA file> <keys folder> <settings file> <libexec>
# Actions (the wrapper's `owner-login <action>`):
#   owner        policy `owner` (create, read, update, delete, list on kv/owner/*, no other path), the OIDC login `oidc`
#                against realm lab (client `openbao`), and role `owner` bound to the owner's user name, 15-minute tokens
#   test         the same with a test role and policy: role `login-test`, policy `login-test` on kv/login-test/* only,
#                bound to the test user (default signin-test)
#   check-test   signs the test user in through Keycloak with its password and one-time code, then writes and reads
#                kv/login-test/probe and must be refused on kv/owner/probe and kv/c1/check; prints PASS or FAIL lines
#   remove-test  deletes role and policy `login-test` and the probe, so the test user can no longer get a token
# The client secret and the test user's password and seed come from the prod identity.env in the keys folder and
# are never printed. Every call uses the admin AppRole (D-0062), so it runs only from the box's /32.
# The policy `owner` gives the owner no path but kv/owner/* (OpenBao's `default` policy, for token self-service and the
# page, still comes with every token).
# Settings (agent_box_secrets_store_prod.owner_login, private inventory): issuer (https://<keycloak>/realms/lab),
# host (the store's name the page is reached at), username (the owner's Keycloak user name), test_username
# (default signin-test). The store's CA file also verifies Keycloak's certificate (both come from the lab CA).
set -euo pipefail
umask 077

action=${1:-} addr=${2:-}/v1 cacert=${3:-} keys=${4:-} settings=${5:-} libexec=${6:-}
die() { echo "secrets-store owner-login $action: $*" >&2; exit 1; }
[[ -n $cacert && -n $keys && -n $settings ]] || die "called without the wrapper's arguments"
case $action in owner | test | check-test | remove-test) ;; *) die "action must be owner, test, check-test or remove-test" ;; esac

# The wrapper's --resolve <store name>:443:<admin address> (D-0062) applies to every curl call here.
curl() { if [[ -n ${SECRETS_STORE_RESOLVE:-} ]]; then command curl --resolve "$SECRETS_STORE_RESOLVE" "$@"; else command curl "$@"; fi; }

find /dev/shm -maxdepth 1 -name 'secrets-store-owner.*' -user "$(id -u)" -exec rm -rf -- {} +
tmp=$(mktemp -d /dev/shm/secrets-store-owner.XXXXXX)
token=''
call() {
  local method=$1 path=$2
  shift 2
  curl -s --connect-timeout 10 --max-time 30 --cacert "$cacert" -X "$method" -H @- "$@" "$addr/$path" <<<"X-Vault-Token: $token"
}
cleanup() {
  [[ -z $token ]] || call POST auth/token/revoke-self -o /dev/null >/dev/null 2>&1 || true
  rm -rf -- "$tmp"
}
trap cleanup EXIT

cfg() { python3 -I -c 'import json,sys; v=json.load(open(sys.argv[1])).get("owner_login",{}).get(sys.argv[2]); print(v if v else sys.argv[3])' "$settings" "$1" "${2:-}"; }
issuer=$(cfg issuer) host=$(cfg host) owner_user=$(cfg username) test_user=$(cfg test_username signin-test)
[[ $issuer =~ ^https://[^/]+/realms/[A-Za-z0-9_-]+$ ]] || die "settings owner_login.issuer must be https://<keycloak>/realms/<realm>"
[[ $host =~ ^[a-z0-9.-]+$ ]] || die "settings owner_login.host must be the store's name"
[[ $owner_user =~ ^[A-Za-z0-9._-]+$ && $test_user =~ ^[A-Za-z0-9._-]+$ ]] || die "settings owner_login.username and test_username must be user names"
redirect="https://$host/ui/vault/auth/oidc/oidc/callback"

# One admin token for the run; the secret ID goes to curl on stdin and neither ID is printed.
python3 -I -c 'import json,sys; print(json.dumps({"role_id": open(sys.argv[1]).read().strip(), "secret_id": open(sys.argv[2]).read().strip()}))' \
  "$keys/openbao-admin-role-id" "$keys/openbao-admin-secret-id" |
  curl -s --connect-timeout 10 --max-time 30 --cacert "$cacert" -X POST --data @- -o "$tmp/login.json" -w '%{http_code}' "$addr/auth/approle/login" > "$tmp/login.code" || true
[[ $(cat "$tmp/login.code" 2>/dev/null) == 200 ]] || die "the admin login answered HTTP $(cat "$tmp/login.code" 2>/dev/null || echo none), not 200 (the box's /32 only, D-0062)"
token=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["auth"]["client_token"])' "$tmp/login.json")

# put_json PATH FILE: POST the file, 200 or 204 or stop.
put_json() {
  local code
  code=$(call POST "$1" --data-binary "@$2" -o "$tmp/reply.json" -w '%{http_code}') || true
  [[ $code == 200 || $code == 204 ]] || die "writing $1 answered HTTP ${code:-nothing}: $(python3 -I -c 'import json,sys; print("; ".join(json.load(open(sys.argv[1])).get("errors",[]))[:200])' "$tmp/reply.json" 2>/dev/null)"
}

policy_for() {  # policy_for NAME PREFIX: all of kv/<prefix>/* and no other path
  cat <<EOF
path "kv/data/$2/*"     { capabilities = ["create", "read", "update", "delete", "list"] }
path "kv/metadata/$2/*" { capabilities = ["read", "list", "delete"] }
path "kv/metadata/$2"   { capabilities = ["list"] }
EOF
}

# setup NAME PREFIX USER: policy, the login, the role.
setup() {
  local name=$1 prefix=$2 user=$3 code
  policy_for "$name" "$prefix" > "$tmp/policy.hcl"
  python3 -I -c 'import json,sys; print(json.dumps({"policy": open(sys.argv[1]).read()}))' "$tmp/policy.hcl" > "$tmp/policy.json"
  put_json "sys/policies/acl/$name" "$tmp/policy.json"
  echo "PASS: policy $name holds kv/$prefix/* only"
  code=$(call GET sys/auth -o "$tmp/auth.json" -w '%{http_code}') || true
  [[ $code == 200 ]] || die "reading sys/auth answered HTTP ${code:-nothing}"
  if ! python3 -I -c 'import json,sys; sys.exit(0 if "oidc/" in json.load(open(sys.argv[1])).get("data", json.load(open(sys.argv[1]))) else 1)' "$tmp/auth.json"; then
    echo '{"type":"oidc"}' > "$tmp/enable.json"
    put_json sys/auth/oidc "$tmp/enable.json"
    echo "PASS: login method oidc enabled"
  fi
  # The client secret never leaves this process except in the body file (private folder in memory).
  python3 -I -c '
import json, sys
env, issuer, ca = sys.argv[1:4]
secret = ""
for l in open(env):
    k, _, v = l.rstrip("\n").partition("=")
    if k == "OPENBAO_CLIENT_SECRET": secret = v.strip().strip("\"'"'"'")
if not secret: sys.exit("OPENBAO_CLIENT_SECRET is not in identity.env")
print(json.dumps({"oidc_discovery_url": issuer, "oidc_client_id": "openbao", "oidc_client_secret": secret,
                  "oidc_discovery_ca_pem": open(ca).read(), "default_role": "owner"}))' \
    "$keys/identity.env" "$issuer" "$cacert" > "$tmp/config.json" || die "could not build the login config"
  put_json auth/oidc/config "$tmp/config.json"
  echo "PASS: auth/oidc/config points at $(printf '%s' "$issuer" | sed 's#//[^/]*#//<keycloak>#') with client openbao"
  python3 -I -c '
import json, sys
name, user, redirect = sys.argv[1:4]
print(json.dumps({"role_type": "oidc", "user_claim": "preferred_username", "bound_claims": {"preferred_username": [user]},
  "oidc_scopes": ["openid"], "allowed_redirect_uris": [redirect], "policies": [name], "token_ttl": "15m", "token_max_ttl": "15m"}))' \
    "$name" "$user" "$redirect" > "$tmp/role.json"
  put_json "auth/oidc/role/$name" "$tmp/role.json"
  echo "PASS: role $name: user $user, policy $name, 15-minute tokens"
}

case $action in
  owner) setup owner owner "$owner_user" ;;
  test) setup login-test login-test "$test_user" ;;
  remove-test)
    # Each DELETE must answer 204 (200 is fine too); the probe may also be 404, if check-test never wrote it.
    for target in auth/oidc/role/login-test sys/policies/acl/login-test kv/metadata/login-test/probe; do
      code=$(call DELETE "$target" -o /dev/null -w '%{http_code}') || true
      [[ $code == 204 || $code == 200 || ( $code == 404 && $target == kv/metadata/login-test/probe ) ]] ||
        die "deleting $target answered HTTP ${code:-nothing}; the test login may still work"
    done
    echo "PASS: role, policy and probe of login-test removed (the Keycloak test user is removed by the identity users run)"
    ;;
  check-test)
    "$libexec/ansible-venv/bin/python3" -I "$libexec/owner-login-check.py" "$addr" "$cacert" "$keys/identity.env" "$issuer" "$redirect" "$test_user" ||
      die "the test sign-in failed; the lines above say where"
    ;;
esac
