#!/bin/bash
# Dev only, for the SSH certificate proof (playbooks/k8s-ssh-ca-proof.yml). Run as root on dev's first
# control-plane node:  ssh-ca-proof.sh <work folder> <issuer> <OpenBao image> <allowed user> <refused user>
# The work folder holds <allowed user>.jwt, <refused user>.jwt (ID tokens from Keycloak) and realm.pem (realm
# lab's signing key), from ssh-ca-proof-token.py.
#
# It starts a throwaway OpenBao in dev mode in namespace ssh-ca-proof (its root token made here, handed over in
# a Secret, never printed), gives it an SSH CA and a JWT login that trusts realm lab and only the allowed user,
# points this node's sshd at the CA for one local account, and checks:
#   the allowed user's Keycloak token gets an OpenBao token; the refused user's does not
#   that token signs a key for the local account and is refused for root
#   ssh with the certificate logs in; the same key without it is refused
#   a certificate past its end time is refused; a revoked one is refused
# Then it removes the namespace, the sshd setting and the account, pass or fail. Prints "ssh-ca: ..." lines only,
# and ends "ssh-ca: PASS: ..." or "ssh-ca: FAIL: ...". Exit 0 on PASS.
set -uo pipefail
umask 077
work=$1 issuer=$2 image=$3 allowed=$4 refused=$5
ns=ssh-ca-proof acct=sshproof
kc() { kubectl --kubeconfig /etc/kubernetes/admin.conf "$@"; }
say() { echo "ssh-ca: $*"; }
fails=0
check() { # name, then a command: ok when it succeeds
  local name=$1; shift
  if "$@"; then say "$name: ok"; else say "$name: FAIL"; fails=$((fails + 1)); fi
}
conf=/etc/ssh/sshd_config.d/05-ssh-ca-proof.conf
cleanup() {
  kc delete namespace "$ns" --wait=false >/dev/null 2>&1 || true
  rm -f "$conf" /etc/ssh/ssh-ca-proof-ca.pub /etc/ssh/ssh-ca-proof.krl
  systemctl reload sshd >/dev/null 2>&1 || true
  userdel -r "$acct" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for f in "$allowed.jwt" "$refused.jwt" realm.pem; do
  [ -s "$work/$f" ] || { say "FAIL: $f is missing from the work folder (the token step failed)"; exit 1; }
done

# 1. The throwaway OpenBao: dev mode, listening on the pod's loopback only, reached through kubectl exec.
kc create namespace "$ns" >/dev/null || { say "FAIL: could not make namespace $ns"; exit 1; }
head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' | kc -n "$ns" create secret generic root --from-file=token=/dev/stdin >/dev/null
kc apply -f - >/dev/null <<EOF || { say "FAIL: could not start the throwaway OpenBao"; exit 1; }
apiVersion: v1
kind: Pod
metadata: {name: bao, namespace: $ns}
spec:
  automountServiceAccountToken: false
  containers:
    - name: bao
      image: $image
      args: [server, -dev, -dev-listen-address=127.0.0.1:8200]
      env:
        - {name: BAO_DEV_ROOT_TOKEN_ID, valueFrom: {secretKeyRef: {name: root, key: token}}}
        - {name: SKIP_SETCAP, value: "true"}
      resources: {requests: {cpu: 50m, memory: 64Mi}, limits: {memory: 256Mi}}
EOF
if ! kc -n "$ns" wait pod/bao --for=condition=Ready --timeout=180s >/dev/null 2>&1; then
  say "FAIL: the throwaway OpenBao did not turn Ready in 180 s"; exit 1
fi
bao_sh() { kc -n "$ns" exec -i bao -- sh -s; }
up=""
for _ in $(seq 1 30); do
  up=$(echo 'BAO_ADDR=http://127.0.0.1:8200 bao status -format=json 2>/dev/null | grep -c "\"initialized\": true"' | bao_sh 2>/dev/null) || true
  [ "$up" = 1 ] && break; sleep 2
done
[ "$up" = 1 ] || { say "FAIL: the throwaway OpenBao did not answer"; exit 1; }
say "openbao: dev-mode store up, image $(printf '%s' "$image" | sed 's/@.*//')"

# 2. The CA, the role (one account, 5 minutes by default) and the JWT login that trusts realm lab.
pem_json=$(python3 -I -c 'import json,sys; print(json.dumps({"jwt_validation_pubkeys": [p + "-----END PUBLIC KEY-----\n" for p in open(sys.argv[1]).read().split("-----END PUBLIC KEY-----\n") if p.strip()], "bound_issuer": sys.argv[2]}))' "$work/realm.pem" "$issuer")
role_json=$(python3 -I -c 'import json,sys; print(json.dumps({"role_type": "jwt", "user_claim": "preferred_username", "bound_audiences": ["grafana"], "bound_claims": {"preferred_username": [sys.argv[1]]}, "token_policies": ["ssh-proof"], "token_ttl": "5m"}))' "$allowed")
setup=$( { cat <<EOF
set -e
export BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="\$BAO_DEV_ROOT_TOKEN_ID"
bao secrets enable -path=ssh-user-ca ssh >/dev/null
bao write -field=public_key ssh-user-ca/config/ca generate_signing_key=true > /tmp/ca.pub
printf '%s' '{"key_type":"ca","allow_user_certificates":true,"allowed_users":"$acct","default_user":"$acct","allowed_extensions":"permit-pty","default_extensions":{"permit-pty":""},"ttl":"5m","max_ttl":"10m"}' | bao write ssh-user-ca/roles/proof - >/dev/null
printf '%s\n' 'path "ssh-user-ca/sign/proof" { capabilities = ["create", "update"] }' | bao policy write ssh-proof - >/dev/null
bao auth enable jwt >/dev/null
printf '%s' '$pem_json' | bao write auth/jwt/config - >/dev/null
printf '%s' '$role_json' | bao write auth/jwt/role/proof - >/dev/null
cat /tmp/ca.pub
EOF
} | bao_sh 2>&1)
ca=$(printf '%s\n' "$setup" | grep -E '^ssh-(rsa|ed25519) ' | tail -n 1)
if [ -z "$ca" ]; then say "FAIL: setting up the CA and the login: $(printf '%s' "$setup" | tr -s '\n' ' ' | cut -c1-200)"; exit 1; fi
say "openbao: SSH CA, role proof (account $acct, 5 min) and JWT login for realm lab's $allowed written"

# Every value below goes into the script text on kubectl exec's stdin, never into an argument. Each is checked
# to hold no quote first: tokens are [A-Za-z0-9._-] and the JSON bodies carry only a public key and names.
safe() { [[ $1 != *"'"* && $1 != *'\\'* ]]; }
# login <user>: an OpenBao token from the user's Keycloak ID token, or nothing.
login() {
  local jwt body
  jwt=$(cat "$work/$1.jwt"); [[ $jwt =~ ^[A-Za-z0-9._-]+$ ]] || return 0
  body=$(printf '{"role":"proof","jwt":"%s"}' "$jwt")
  printf "export BAO_ADDR=http://127.0.0.1:8200\nprintf '%%s' '%s' | bao write -field=token auth/jwt/login - 2>/dev/null\n" "$body" |
    bao_sh 2>/dev/null | grep -E '^[A-Za-z0-9._-]+$' | head -n 1
}
# sign <bao token file> <public key file> <principal> <ttl> <out>: the signed certificate, or a failure.
sign() {
  local tok body
  tok=$(cat "$1"); [[ $tok =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  body=$(python3 -I -c 'import json,sys; print(json.dumps({"public_key": open(sys.argv[1]).read().strip(), "valid_principals": sys.argv[2], "ttl": sys.argv[3]}))' "$2" "$3" "$4")
  safe "$body" || return 1
  printf "export BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN='%s'\nprintf '%%s' '%s' | bao write -field=signed_key ssh-user-ca/sign/proof - 2>/dev/null\n" "$tok" "$body" |
    bao_sh > "$5" 2>/dev/null
  grep -q '^ssh-.*-cert-v01@openssh.com ' "$5"
}

tok_ok=$(login "$allowed"); tok_no=$(login "$refused")
check "login: $allowed's Keycloak token gets an OpenBao token" test -n "$tok_ok"
check "login: $refused's Keycloak token is refused" test -z "$tok_no"
printf '%s' "$tok_ok" > "$work/bao.tok"

# 3. This node's sshd trusts the CA, for one local account only by the role's allowed_users; a revocation list.
useradd -m -s /bin/bash "$acct" >/dev/null 2>&1 || true
printf '%s\n' "$ca" > /etc/ssh/ssh-ca-proof-ca.pub
ssh-keygen -q -k -f /etc/ssh/ssh-ca-proof.krl
chmod 644 /etc/ssh/ssh-ca-proof-ca.pub /etc/ssh/ssh-ca-proof.krl
printf 'TrustedUserCAKeys /etc/ssh/ssh-ca-proof-ca.pub\nRevokedKeys /etc/ssh/ssh-ca-proof.krl\n' > "$conf"
chmod 600 "$conf"
if ! sshd -t >/dev/null 2>&1; then say "FAIL: sshd rejects the setting"; exit 1; fi
systemctl reload sshd
sleep 2

ssh-keygen -q -t ed25519 -N '' -C proof-1 -f "$work/k1"
ssh-keygen -q -t ed25519 -N '' -C proof-2 -f "$work/k2"
try() { # key, cert or "", expected output or "": ok when ssh's result matches
  # ssh also loads <key>-cert.pub beside a key on its own, so "without the certificate" uses a copy of the key alone.
  local key=$1
  if [ -z "$2" ]; then mkdir -p "$work/bare"; cp "$1" "$work/bare/key"; key=$work/bare/key; fi
  local o=(-F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i "$key")
  [ -z "$2" ] || o+=(-o "CertificateFile=$2")
  local out
  out=$(ssh "${o[@]}" "$acct@127.0.0.1" id -un 2>/dev/null) || true
  [ "$out" = "$3" ]
}
check "sign: the token signs a key for $acct" sign "$work/bao.tok" "$work/k1.pub" "$acct" 5m "$work/k1-cert.pub"
refuses() { ! "$@"; }
check "sign: the token is refused for root" refuses sign "$work/bao.tok" "$work/k1.pub" root 5m "$work/root-cert.pub"
[ -s "$work/k1-cert.pub" ] && say "cert: $(ssh-keygen -L -f "$work/k1-cert.pub" | grep -E 'Valid:' | sed 's/^ *//')"
check "ssh: the certificate logs in as $acct" try "$work/k1" "$work/k1-cert.pub" "$acct"
check "ssh: the same key without the certificate is refused" try "$work/k1" "" ""
check "sign: a 20-second certificate" sign "$work/bao.tok" "$work/k2.pub" "$acct" 20s "$work/k2-cert.pub"
sleep 25
check "ssh: the certificate past its end time is refused" try "$work/k2" "$work/k2-cert.pub" ""
ssh-keygen -q -k -u -f /etc/ssh/ssh-ca-proof.krl "$work/k1-cert.pub"
check "ssh: the revoked certificate is refused" try "$work/k1" "$work/k1-cert.pub" ""

if [ "$fails" -eq 0 ]; then say "PASS: Keycloak sign-in, OpenBao certificate, ssh login, expiry and revocation"; exit 0; fi
say "FAIL: $fails check(s) failed"; exit 1
