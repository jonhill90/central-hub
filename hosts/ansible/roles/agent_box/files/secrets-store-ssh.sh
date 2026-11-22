#!/bin/bash
# /usr/local/libexec/agent-box/secrets-store-ssh.sh: the SSH certificate sign-in for the lab's Linux boxes (D-0064),
# set up from the box. Called by secrets-store.sh (never directly), as user `keys`, with:
#   secrets-store-ssh.sh <action> <store address> <CA file> <keys folder> <settings file> <libexec> [args...]
# Actions (the wrapper's `ssh-ca <action>`):
#   plan        prints where each value comes from; makes no call and prints no name
#   apply       mounts ssh-user and ssh-host, makes each CA key inside the store when it has none (never replaces one),
#               writes role `admin` (user certificates, principal lab-admin, 1 hour) and role `hosts` (host certificates),
#               policy `ssh-sign` (create and update on ssh-user/sign/admin, nothing else) and the OIDC login role
#               `ssh-admin`, bound to Keycloak group lab-admins (D-0064 rules 1 to 3). Safe to run again.
#   check       reads all of it back and compares it with what apply writes; prints PASS or FAIL lines
#   public      writes the two CA public keys (not secrets) to <keys folder>/ssh-ca/user-ca.pub and host-ca.pub
#   sign-host   <names, comma separated>, the box's host public key on stdin: signs it for those names and writes
#               <keys folder>/ssh-ca/host-<first name>-cert.pub
# Both writes go only into that one folder, which this helper makes; a session names no path (the reviewer's ask on #883).
# (The wrapper also passes its libexec folder as the sixth argument; this helper does not use it.)
# Every call uses the admin AppRole (D-0062), so it runs only from the box's /32. No token, ID or secret is printed.
# Values: the settings' ssh_ca keys (admin_group, principal, user_ttl, host_ttl, zone, redirect) override what the
# wrapper derives from the inventory (zone, as for owner-login).
set -euo pipefail
umask 077

action=${1:-} addr=${2:-}/v1 cacert=${3:-} keys=${4:-} settings=${5:-}
shift 6 2>/dev/null || true
die() { echo "secrets-store ssh-ca $action: $*" >&2; exit 1; }
[[ -n $cacert && -n $keys && -n $settings ]] || die "called without the wrapper's arguments"
case $action in plan | apply | check | public | sign-host) ;; *) die "action must be plan, apply, check, public or sign-host" ;; esac

curl() { if [[ -n ${SECRETS_STORE_RESOLVE:-} ]]; then command curl --resolve "$SECRETS_STORE_RESOLVE" "$@"; else command curl "$@"; fi; }

cfg() { python3 -I -c 'import json,sys; v=json.load(open(sys.argv[1])).get("ssh_ca",{}).get(sys.argv[2]); print(v if v else sys.argv[3])' "$settings" "$1" "${2:-}"; }
admin_group=$(cfg admin_group lab-admins)
principal=$(cfg principal lab-admin)
user_ttl=$(cfg user_ttl 1h)
host_ttl=$(cfg host_ttl 720h)
zone=$(cfg zone "${SSH_CA_ZONE:-}")
redirect=$(cfg redirect http://localhost:8250/oidc/callback)
for v in "$admin_group" "$principal"; do [[ $v =~ ^[A-Za-z0-9._-]+$ ]] || die "a group or principal name may hold letters, digits, ., _ and - only"; done
for v in "$user_ttl" "$host_ttl"; do [[ $v =~ ^[0-9]+[smh]$ ]] || die "a life must be a number and s, m or h"; done
[[ $redirect =~ ^http://localhost:[0-9]{2,5}/oidc/callback$ ]] || die "the redirect must be the CLI's http://localhost:<port>/oidc/callback"
if [[ $action == plan ]]; then
  echo "plan: group $([[ -n $(cfg admin_group) ]] && echo 'from settings' || echo 'default lab-admins')"
  echo "plan: principal $([[ -n $(cfg principal) ]] && echo 'from settings' || echo 'default lab-admin')"
  echo "plan: user certificate life $user_ttl (default 1h), host certificate life $host_ttl (default 720h)"
  echo "plan: zone for host names from $([[ -n $(cfg zone) ]] && echo settings || echo "${SSH_CA_ZONE_KEY:-nothing: set ssh_ca.zone or a plain zone in the inventory}")"
  exit 0
fi
[[ -n $zone || $action != apply ]] || die "no zone for host names: set ssh_ca.zone, or a plain zone in the inventory (k8s_gitops_source_zone, k8s_identity_zone or k8s_gateway_zone)"
[[ -z $zone || $zone =~ ^[a-z0-9.-]+$ ]] || die "the zone must be lowercase letters, digits, . and -"
[[ $action != apply ]] || [[ $(cfg issuer "${SSH_CA_ISSUER:-}") =~ ^https://[^/]+/realms/[A-Za-z0-9_-]+$ ]] || die "no Keycloak issuer: set ssh_ca.issuer, or a plain zone in the inventory"

find /dev/shm -maxdepth 1 -name 'secrets-store-ssh.*' -user "$(id -u)" -exec rm -rf -- {} +
tmp=$(mktemp -d /dev/shm/secrets-store-ssh.XXXXXX)
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

python3 -I -c 'import json,sys; print(json.dumps({"role_id": open(sys.argv[1]).read().strip(), "secret_id": open(sys.argv[2]).read().strip()}))' \
  "$keys/openbao-admin-role-id" "$keys/openbao-admin-secret-id" |
  curl -s --connect-timeout 10 --max-time 30 --cacert "$cacert" -X POST --data @- -o "$tmp/login.json" -w '%{http_code}' "$addr/auth/approle/login" > "$tmp/login.code" || true
[[ $(cat "$tmp/login.code" 2>/dev/null) == 200 ]] || die "the admin login answered HTTP $(cat "$tmp/login.code" 2>/dev/null || echo none), not 200 (the box's /32 only, D-0062)"
token=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["auth"]["client_token"])' "$tmp/login.json")

put_json() {  # put_json PATH FILE: POST the file, 200 or 204 or stop
  local code
  code=$(call POST "$1" --data-binary "@$2" -o "$tmp/reply.json" -w '%{http_code}') || true
  [[ $code == 200 || $code == 204 ]] || die "writing $1 answered HTTP ${code:-nothing}: $(python3 -I -c 'import json,sys; print("; ".join(json.load(open(sys.argv[1])).get("errors",[]))[:200])' "$tmp/reply.json" 2>/dev/null)"
}
jq_() { python3 -I -c "$1" "${@:2}"; }  # a tiny json reader: jq_ 'code using sys.argv[1] as the file' FILE...

# What each role and policy holds. One place, so apply writes and check compares the same text.
user_role() { jq_ 'import json,sys; print(json.dumps({"key_type":"ca","allow_user_certificates":True,"allowed_users":sys.argv[1],"default_user":sys.argv[1],"allow_user_key_ids":False,"key_id_format":"{{token_display_name}}","allowed_extensions":"permit-pty","default_extensions":{"permit-pty":""},"allowed_critical_options":"","ttl":sys.argv[2],"max_ttl":sys.argv[2],"algorithm_signer":"default"}))' "$principal" "$user_ttl"; }
host_role() { jq_ 'import json,sys; print(json.dumps({"key_type":"ca","allow_host_certificates":True,"allow_user_certificates":False,"allowed_domains":sys.argv[1],"allow_subdomains":True,"allow_bare_domains":True,"ttl":sys.argv[2],"max_ttl":sys.argv[2],"algorithm_signer":"default"}))' "$zone" "$host_ttl"; }
sign_policy() { echo 'path "ssh-user/sign/admin" { capabilities = ["create", "update"] }'; }

mounts() { code=$(call GET sys/mounts -o "$tmp/mounts.json" -w '%{http_code}') || true; [[ $code == 200 ]] || die "reading sys/mounts answered HTTP ${code:-nothing}"; }
has_mount() { jq_ 'import json,sys; d=json.load(open(sys.argv[1])); d=d.get("data",d); sys.exit(0 if sys.argv[2]+"/" in d else 1)' "$tmp/mounts.json" "$1"; }
has_ca() {  # has_ca MOUNT: the mount has a default issuer (GET config/ca answers 200 with a public key)
  local code
  code=$(call GET "$1/config/ca" -o "$tmp/ca.json" -w '%{http_code}') || true
  [[ $code == 200 ]] && jq_ 'import json,sys; d=json.load(open(sys.argv[1])).get("data",{}); sys.exit(0 if d.get("public_key","").startswith("ssh-") else 1)' "$tmp/ca.json"
}

case $action in
  apply)
    mounts
    for m in ssh-user ssh-host; do
      if ! has_mount "$m"; then echo '{"type":"ssh"}' > "$tmp/mount.json"; put_json "sys/mounts/$m" "$tmp/mount.json"; echo "PASS: mount $m made"; fi
      # POST config/ca on a mount that has a CA replaces it (OpenBao API docs, "Submit CA information"), so it is made only when there is none.
      if has_ca "$m"; then echo "PASS: $m already has its CA key (kept, never replaced)"
      else
        echo '{"generate_signing_key":true,"key_type":"ssh-ed25519"}' > "$tmp/ca-new.json"
        put_json "$m/config/ca" "$tmp/ca-new.json"; echo "PASS: $m made its CA key inside the store (ed25519)"
      fi
    done
    user_role > "$tmp/r1.json"; put_json ssh-user/roles/admin "$tmp/r1.json"
    echo "PASS: ssh-user role admin: principal $principal only, $user_ttl, permit-pty only, key ID from the token's name"
    host_role > "$tmp/r2.json"; put_json ssh-host/roles/hosts "$tmp/r2.json"
    echo "PASS: ssh-host role hosts: names under the zone only, $host_ttl"
    sign_policy > "$tmp/policy.hcl"
    jq_ 'import json,sys; print(json.dumps({"policy": open(sys.argv[1]).read()}))' "$tmp/policy.hcl" > "$tmp/policy.json"
    put_json sys/policies/acl/ssh-sign "$tmp/policy.json"
    echo "PASS: policy ssh-sign: create and update on ssh-user/sign/admin, no other path"
    # The OIDC login: owner-login makes mount oidc and its config; ssh-admin is one more role on it.
    code=$(call GET auth/oidc/config -o "$tmp/oidc.json" -w '%{http_code}') || true
    [[ $code == 200 ]] || die "auth/oidc is not configured (HTTP ${code:-none}); run owner-login first, it makes the login and its Keycloak client"
    jq_ 'import json,sys; print(json.dumps({"role_type":"oidc","user_claim":"preferred_username","groups_claim":"groups","bound_claims":{"groups":[sys.argv[1]]},"oidc_scopes":["openid"],"allowed_redirect_uris":[sys.argv[2]],"policies":["ssh-sign"],"token_ttl":"15m","token_max_ttl":"15m"}))' "$admin_group" "$redirect" > "$tmp/oidc-role.json"
    put_json auth/oidc/role/ssh-admin "$tmp/oidc-role.json"
    echo "PASS: login role ssh-admin: Keycloak group $admin_group, redirect $redirect, 15-minute tokens, policy ssh-sign"
    ;;
  check)
    fails=0
    chk() { if "${@:2}"; then echo "PASS: $1"; else echo "FAIL: $1"; fails=$((fails + 1)); fi; }
    mounts
    chk "mount ssh-user" has_mount ssh-user
    chk "mount ssh-host" has_mount ssh-host
    chk "ssh-user has a CA key" has_ca ssh-user
    chk "ssh-host has a CA key" has_ca ssh-host
    same() {  # same PATH EXPECTED_JSON_FILE: the fields that are plain text or flags read back equal (lives are not compared: the store may show seconds)
      local code
      code=$(call GET "$1" -o "$tmp/read.json" -w '%{http_code}') || true
      [[ $code == 200 ]] && jq_ 'import json,sys; got=json.load(open(sys.argv[1])).get("data",{}); want=json.load(open(sys.argv[2])); keys=[k for k in want if k not in ("ttl","max_ttl","key_id_format","algorithm_signer","allowed_critical_options")]; sys.exit(0 if all(got.get(k)==want[k] for k in keys) else 1)' "$tmp/read.json" "$2"
    }
    user_role > "$tmp/e1.json"; chk "role ssh-user/roles/admin reads back as written" same ssh-user/roles/admin "$tmp/e1.json"
    host_role > "$tmp/e2.json"; chk "role ssh-host/roles/hosts reads back as written" same ssh-host/roles/hosts "$tmp/e2.json"
    code=$(call GET sys/policies/acl/ssh-sign -o "$tmp/pol.json" -w '%{http_code}') || true
    chk "policy ssh-sign is exactly the one path" jq_ 'import json,sys; d=json.load(open(sys.argv[1])); d=d.get("data",d); sys.exit(0 if d.get("policy","").strip()==sys.argv[2] else 1)' "$tmp/pol.json" "$(sign_policy)"
    code=$(call GET auth/oidc/role/ssh-admin -o "$tmp/oidc-role.json" -w '%{http_code}') || true
    chk "login role ssh-admin is bound to $admin_group and holds only ssh-sign" jq_ 'import json,sys; d=json.load(open(sys.argv[1])).get("data",{}); sys.exit(0 if d.get("bound_claims")=={"groups":[sys.argv[2]]} and d.get("token_policies",d.get("policies"))==["ssh-sign"] and d.get("allowed_redirect_uris")==[sys.argv[3]] else 1)' "$tmp/oidc-role.json" "$admin_group" "$redirect"
    [[ $fails -eq 0 ]] || die "$fails check(s) failed"
    echo "PASS: ssh-ca set-up reads back as written"
    ;;
  public)
    out=$keys/ssh-ca
    mkdir -p "$out"; chmod 755 "$out"
    for pair in ssh-user:user-ca.pub ssh-host:host-ca.pub; do
      m=${pair%%:*}
      has_ca "$m" || die "$m has no CA key; run apply first"
      jq_ 'import json,sys; print(json.load(open(sys.argv[1]))["data"]["public_key"].strip())' "$tmp/ca.json" > "$out/${pair##*:}"
      chmod 644 "$out/${pair##*:}"
      echo "PASS: ssh-ca/${pair##*:} written ($(cut -d' ' -f1 "$out/${pair##*:}"))"
    done
    ;;
  sign-host)
    names=${1:-}
    [[ $names =~ ^[A-Za-z0-9][A-Za-z0-9.,-]*$ ]] || die "sign-host needs the names (letters, digits, ., , and -), and the host public key on stdin"
    head -c 4096 > "$tmp/host.pub"
    [[ $(wc -l < "$tmp/host.pub") -le 1 && $(head -c 3 "$tmp/host.pub") == ssh ]] || die "stdin must be one public key line"
    host_role > /dev/null
    jq_ 'import json,sys; print(json.dumps({"public_key": open(sys.argv[1]).read().strip(), "cert_type": "host", "valid_principals": sys.argv[2], "ttl": sys.argv[3]}))' "$tmp/host.pub" "$names" "$host_ttl" > "$tmp/sign.json"
    code=$(call POST ssh-host/sign/hosts --data-binary "@$tmp/sign.json" -o "$tmp/signed.json" -w '%{http_code}') || true
    [[ $code == 200 ]] || die "signing answered HTTP ${code:-nothing}"
    mkdir -p "$keys/ssh-ca"; chmod 755 "$keys/ssh-ca"
    out="$keys/ssh-ca/host-${names%%,*}-cert.pub"
    jq_ 'import json,sys; print(json.load(open(sys.argv[1]))["data"]["signed_key"].strip())' "$tmp/signed.json" > "$out"
    grep -q '^ssh-.*-cert-v01@openssh.com ' "$out" || { rm -f "$out"; die "the answer holds no certificate"; }
    chmod 644 "$out"
    echo "PASS: host certificate for $names written to ssh-ca/host-${names%%,*}-cert.pub ($host_ttl)"
    ;;
esac
