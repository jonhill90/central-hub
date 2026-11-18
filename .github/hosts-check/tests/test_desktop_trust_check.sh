#!/bin/bash
# Tests for hosts/ansible/roles/desktop/files/desktop-trust-check.sh, the desktop's trust check before its admin
# key is removed. A throwaway root and intermediate, a server certificate for localhost, and a local TLS server:
#   1. a bundle with the root verifies the chain, and a name served under it passes;
#   2. a bundle without the root fails the chain check;
#   3. a name served by an untrusted certificate fails as TLS, and a closed port fails as not reached.
# curl reads CURL_CA_BUNDLE in place of the system store, so the test needs no root.
set -euo pipefail
here=$(cd "$(dirname "$0")/../../.." && pwd)
check=$here/hosts/ansible/roles/desktop/files/desktop-trust-check.sh
t=$(mktemp -d)
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; rm -rf "$t"; }
trap cleanup EXIT
cd "$t"
unset HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy
export NO_PROXY='*'

ossl() { openssl "$@" 2>/dev/null; }
ossl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout root.key -out root.crt -days 2 \
  -subj "/CN=Test Lab Root CA" -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign
ossl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout int.key -out int.csr -subj "/CN=Test Lab Intermediate CA"
printf 'basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n' >int.ext
ossl x509 -req -in int.csr -CA root.crt -CAkey root.key -CAcreateserial -out int.crt -days 2 -extfile int.ext
ossl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout srv.key -out srv.csr -subj "/CN=localhost"
printf 'subjectAltName=DNS:localhost\nextendedKeyUsage=serverAuth\n' >srv.ext
ossl x509 -req -in srv.csr -CA int.crt -CAkey int.key -CAcreateserial -out srv.crt -days 2 -extfile srv.ext
cat int.crt root.crt >chain.pem            # as the box's c1-intermediate-chain.crt: intermediate first, root last
ossl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout other.key -out other.crt -days 2 \
  -subj "/CN=localhost" -addext subjectAltName=DNS:localhost
other=$(mktemp -d "$t/o.XXXX")
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$other/r.key" -out "$other/r.crt" \
  -days 2 -subj "/CN=Some Other Root" >/dev/null 2>&1
cp "$other/r.crt" without-root.pem          # a bundle that holds some root, but not the lab's
cat "$other/r.crt" root.crt >with-root.pem  # the system bundle after the lab root is added

port() { python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
serve() { # cert key [openssl s_server options] -> port
  local p c=$1 k=$2; p=$(port); shift 2
  openssl s_server -quiet -www -accept "127.0.0.1:$p" -cert "$c" -key "$k" "$@" >/dev/null 2>&1 &
  pids+=($!)
  for _ in $(seq 50); do (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null && break; sleep 0.1; done
  echo "$p"
}
good=$(serve srv.crt srv.key -cert_chain int.crt)   # sends the intermediate, as the Gateway does
bad=$(serve other.crt other.key)
closed=$(port)

fails=0
expect() { # description, wanted rc, pattern, command...
  local what=$1 want=$2 pat=$3 out rc; shift 3
  set +e; out=$("$@" 2>&1); rc=$?; set -e
  if [[ $rc -eq $want ]] && grep -qE -- "$pat" <<<"$out"; then echo "ok: $what"
  else echo "FAIL: $what (rc $rc, wanted $want; pattern $pat)"; echo "$out" | sed 's/^/  /'; fails=$((fails + 1)); fi
}

export CURL_CA_BUNDLE=$t/with-root.pem
expect "the chain verifies with the lab root in the bundle" 0 \
  '^desktop trust: the system store verifies the lab chain \(.*Test Lab Intermediate CA\)$' \
  sh "$check" chain.pem with-root.pem
expect "a name under the lab root passes, one line" 0 \
  "^desktop trust: localhost:$good: 200, certificate verified$" \
  sh "$check" chain.pem with-root.pem "localhost:$good"
expect "the last line says every check passed" 0 '^desktop trust: every check passed$' \
  sh "$check" chain.pem with-root.pem "localhost:$good"
expect "the chain fails without the lab root" 1 '^desktop trust: the system store does not verify the lab chain' \
  sh "$check" chain.pem without-root.pem
expect "a name with an untrusted certificate fails as TLS" 1 "^desktop trust: localhost:$bad: TLS failed \(curl exit 60\)" \
  sh "$check" chain.pem with-root.pem "localhost:$bad"
expect "a closed port fails as not reached" 1 "^desktop trust: localhost:$closed: not reached \(curl exit 7\)" \
  sh "$check" chain.pem with-root.pem "localhost:$closed"
expect "one failing name fails the run while the others pass" 1 '^desktop trust: a check failed$' \
  sh "$check" chain.pem with-root.pem "localhost:$good" "localhost:$bad"
expect "no arguments is a usage error" 2 '^usage:' sh "$check"
# The intermediate alone in the bundle must not count as trust: openssl verify needs a self-signed anchor.
cp int.crt int-only.pem
expect "the intermediate alone in the bundle does not verify the chain" 1 'does not verify the lab chain' \
  sh "$check" chain.pem int-only.pem

if [[ $fails -gt 0 ]]; then echo "desktop trust check: $fails test(s) failed"; exit 1; fi
echo "desktop trust check: all tests passed"
