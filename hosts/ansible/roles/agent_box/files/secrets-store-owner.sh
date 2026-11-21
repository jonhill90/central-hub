#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store-owner.sh: the owner's sign-in to the secrets store's web page, through
# Keycloak (OIDC), set up and proved from the box. Called by secrets-store.sh (never directly), as user `keys`, with:
#   secrets-store-owner.sh <action> <store address> <CA file> <keys folder> <settings file> <libexec>
# Actions (the wrapper's `owner-login <action>`):
#   owner        policy `owner` (create, read, update, delete, list on kv/owner/* and kv/c1/*, no other path), the OIDC login `oidc`
#                against realm lab (client `openbao`), and role `owner` bound to the owner's user name, 15-minute tokens
#   test         the same with a test role and policy: role `login-test`, policy `login-test` on kv/login-test/* only,
#                bound to the test user (default signin-test)
#   check-test   signs the test user in through Keycloak with its password and one-time code, then writes and reads
#                kv/login-test/probe and must be refused on kv/owner/probe and kv/c1/check; prints PASS or FAIL lines
#   remove-test  deletes role and policy `login-test` and the probe, so the test user can no longer get a token
# The client secret and the test user's password and seed come from the prod identity.env in the keys folder and
# are never printed. Every call uses the admin AppRole (D-0062), so it runs only from the box's /32.
# The policy `owner` gives the owner no path but kv/owner/* and kv/c1/* (the secrets the apps read) (OpenBao's `default` policy, for token self-service and the
# page, still comes with every token).
# Values (see plan): the settings agent_box_secrets_store_prod.owner_login override; else the prod inventory gives them.
# The store's CA file also verifies Keycloak's certificate (both come from the lab CA).
set -euo pipefail
umask 077

action=${1:-} addr=${2:-}/v1 cacert=${3:-} keys=${4:-} settings=${5:-} libexec=${6:-}
die() { echo "secrets-store owner-login $action: $*" >&2; exit 1; }
[[ -n $cacert && -n $keys && -n $settings ]] || die "called without the wrapper's arguments"
case $action in owner | test | check-test | remove-test | plan) ;; *) die "action must be owner, test, check-test, remove-test or plan" ;; esac

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

# Each value is the settings' (owner_login in the private inventory) when set, else derived from what the prod inventory
# already holds: the zone (OWNER_LOGIN_ZONE, from the first of k8s_gitops_source_zone, k8s_identity_zone and k8s_gateway_zone
# that is one plain value) and the owner's user name (OWNER_LOGIN_USER, from k8s_identity_owner_username). Keycloak's name and
# realm are the identity role's defaults (sso, lab; settings keycloak_name and realm override), the page's name is
# openbao.<zone>, and the test user is signin-test.
cfg() { python3 -I -c 'import json,sys; v=json.load(open(sys.argv[1])).get("owner_login",{}).get(sys.argv[2]); print(v if v else sys.argv[3])' "$settings" "$1" "${2:-}"; }
zone=${OWNER_LOGIN_ZONE:-}
issuer=$(cfg issuer) host=$(cfg host) owner_user=$(cfg username "${OWNER_LOGIN_USER:-}") test_user=$(cfg test_username signin-test)
src_issuer=settings src_host=settings src_user=settings
if [[ -z $issuer ]]; then
  [[ -n $zone ]] || die "no issuer: set owner_login.issuer, or a plain zone in the inventory (k8s_gitops_source_zone, k8s_identity_zone or k8s_gateway_zone)"
  issuer="https://$(cfg keycloak_name sso).$zone/realms/$(cfg realm lab)" src_issuer="the zone from ${OWNER_LOGIN_ZONE_KEY:-the inventory}, name and realm of the identity role"
fi
if [[ -z $host ]]; then
  [[ -n $zone ]] || die "no page name: set owner_login.host, or a plain zone in the inventory (k8s_gitops_source_zone, k8s_identity_zone or k8s_gateway_zone)"
  host="openbao.$zone" src_host="openbao. and the zone from ${OWNER_LOGIN_ZONE_KEY:-the inventory}"
fi
if [[ -z $owner_user ]]; then
  [[ $action == plan || $action == test || $action == check-test || $action == remove-test ]] || die "no owner user name: set owner_login.username, or k8s_identity_owner_username in the inventory"
  src_user="none (only owner needs it)"
elif [[ -n ${OWNER_LOGIN_USER:-} && $owner_user == "$OWNER_LOGIN_USER" ]]; then src_user="k8s_identity_owner_username in the inventory"; fi
[[ $issuer =~ ^https://[^/]+/realms/[A-Za-z0-9_-]+$ ]] || die "the issuer must be https://<keycloak>/realms/<realm>"
[[ $host =~ ^[a-z0-9.-]+$ ]] || die "the page's name must be lowercase letters, digits, . and -"
[[ -z $owner_user && $action != owner ]] || [[ $owner_user =~ ^[A-Za-z0-9._-]+$ ]] || die "the owner's user name must be letters, digits, ., _ and -"
[[ $test_user =~ ^[A-Za-z0-9._-]+$ ]] || die "owner_login.test_username must be a user name"
if [[ $action == plan ]]; then
  # No value is printed: the names are private. Only where each one comes from, so the missing ones can be set.
  echo "plan: issuer from $src_issuer"
  echo "plan: page name from $src_host"
  echo "plan: owner user name from $src_user"
  echo "plan: test user name from $([[ -n $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("owner_login",{}).get("test_username",""))' "$settings") ]] && echo settings || echo "the default (signin-test)")"
  exit 0
fi
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

policy_for() {  # policy_for NAME "PREFIX...": all of kv/<prefix>/* for each prefix, and no other path
  local p
  for p in $2; do
    cat <<EOF
path "kv/data/$p/*"     { capabilities = ["create", "read", "update", "delete", "list"] }
path "kv/metadata/$p/*" { capabilities = ["read", "list", "delete"] }
path "kv/metadata/$p"   { capabilities = ["list"] }
EOF
    # kv/c1/check is the word the empty-store guards look for (restore, reseed): read only, so it can't be changed or deleted.
    if [[ $p == c1 ]]; then
      cat <<EOF
path "kv/data/c1/check"     { capabilities = ["read"] }
path "kv/metadata/c1/check" { capabilities = ["read", "list"] }
EOF
    fi
  done
}

# setup NAME "PREFIX..." USER: policy, the login, the role.
setup() {
  local name=$1 prefix=$2 user=$3 code
  policy_for "$name" "$prefix" > "$tmp/policy.hcl"
  python3 -I -c 'import json,sys; print(json.dumps({"policy": open(sys.argv[1]).read()}))' "$tmp/policy.hcl" > "$tmp/policy.json"
  put_json "sys/policies/acl/$name" "$tmp/policy.json"
  echo "PASS: policy $name written, create/read/update/delete/list under kv/ for: $prefix (and no other path)"
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
  # The owner writes his own area and the secrets the apps read (kv/c1/*): his tap of 2026-11-21 00:40 UTC.
  owner) setup owner "owner c1" "$owner_user" ;;
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
