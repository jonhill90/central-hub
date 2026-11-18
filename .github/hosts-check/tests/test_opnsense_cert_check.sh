#!/usr/bin/env bash
# The box's check of the certificate the firewall's web UI serves (hosts/ansible/roles/agent_box/files/opnsense-cert-check.sh),
# against a local `openssl s_server` with certificates made here (test values only, none of the lab's):
#   1. A certificate that verifies against the chain and has more than 45 days left: exit 0, a line with the days and "verified yes".
#   2. One with 10 days left: exit 1, WARN, and the line says fewer than 45 days.
#   3. One a different CA signed: exit 1, WARN, "does not verify".
#   4. With no chain file, the system store decides: a CA it does not hold fails the run, and nothing is claimed verified.
#   5. With nothing listening: exit 1, WARN, "no certificate could be read".
#   6. No settings file, a host setting that is not a name: exit 1, nothing connected to.
#   7. `status` prints the last saved line; before any check it exits 1. Any other argument exits 2.
#   8. Nothing printed holds the host's name.
# Usage: .github/hosts-check/tests/test_opnsense_cert_check.sh   (needs openssl, python3)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
root=$PWD
t=$(mktemp -d)
pids=()
cleanup() { for p in "${pids[@]+"${pids[@]}"}"; do kill "$p" 2>/dev/null; done; rm -rf "$t"; }
trap cleanup EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/work" "$t/keys"
port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
sed -e "s|^work=.*|work=$t/work|" -e "s|^chain=.*|chain=$t/keys/chain.crt|" -e "s|^port=.*|port=$port|" \
    "$root/hosts/ansible/roles/agent_box/files/opnsense-cert-check.sh" > "$t/check.sh"
grep -q "^port=$port" "$t/check.sh" && grep -q "^work=$t/work" "$t/check.sh" || { echo "FAIL: the test could not point the script at its folders"; exit 1; }
check() { bash "$t/check.sh" "$@"; }
echo '{"host": "localhost", "keep": 14}' > "$t/work/opnsense-backup.json"

# make_ca <name>: a CA; make_leaf <ca name> <days>: a certificate for localhost it signs.
make_ca() { openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 365 -subj "/CN=Test $1" -keyout "$t/$1.key" -out "$t/$1.crt" 2>/dev/null; }
make_leaf() {
  openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -subj "/CN=localhost" -keyout "$t/leaf-$1-$2.key" -out "$t/leaf-$1-$2.csr" 2>/dev/null
  printf 'subjectAltName=DNS:localhost\n' > "$t/ext.cnf"
  openssl x509 -req -in "$t/leaf-$1-$2.csr" -CA "$t/$1.crt" -CAkey "$t/$1.key" -CAcreateserial -days "$2" -extfile "$t/ext.cnf" \
    -out "$t/leaf-$1-$2.crt" 2>/dev/null
}
serve() { # <ca name> <days>: stops any earlier server, starts one with that certificate
  for p in "${pids[@]+"${pids[@]}"}"; do kill "$p" 2>/dev/null; done; pids=()
  openssl s_server -accept "127.0.0.1:$port" -cert "$t/leaf-$1-$2.crt" -key "$t/leaf-$1-$2.key" -www -quiet >/dev/null 2>&1 &
  pids+=("$!")
  for _ in $(seq 1 50); do (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && break; sleep 0.1; done
}
make_ca lab; make_ca other
make_leaf lab 100; make_leaf lab 10; make_leaf other 100
cp "$t/lab.crt" "$t/keys/chain.crt"

# 1
serve lab 100
check check > "$t/1.out" 2>&1; rc=$?
if [ $rc = 0 ] && grep -qE '^opnsense-cert-check: notAfter [0-9-]{10}, (99|100) days left, verified yes$' "$t/1.out"; then ok "1 a verified certificate with more than 45 days: exit 0 and the days"; else bad "1 rc=$rc $(cat "$t/1.out")"; fi

# 2
serve lab 10
check check > "$t/2.out" 2>&1; rc=$?
if [ $rc = 1 ] && grep -qE '^WARN .* (9|10) days left, verified yes; fewer than 45 days' "$t/2.out"; then ok "2 10 days left: exit 1 and a WARN naming the 45 days"; else bad "2 rc=$rc $(cat "$t/2.out")"; fi

# 3
serve other 100
check check > "$t/3.out" 2>&1; rc=$?
if [ $rc = 1 ] && grep -q '^WARN .*does not verify against the lab chain' "$t/3.out"; then ok "3 a certificate another CA signed: exit 1, does not verify"; else bad "3 rc=$rc $(cat "$t/3.out")"; fi

# 4
serve lab 100
mv "$t/keys/chain.crt" "$t/chain.away"
check check > "$t/4.out" 2>&1; rc=$?
if [ $rc = 1 ] && grep -q '^WARN .*does not verify against the lab chain' "$t/4.out"; then
  ok "4 no chain file and a CA the system store lacks: exit 1, nothing claimed verified"; else bad "4 rc=$rc $(cat "$t/4.out")"; fi
mv "$t/chain.away" "$t/keys/chain.crt"

# 5
for p in "${pids[@]+"${pids[@]}"}"; do kill "$p" 2>/dev/null; done; pids=(); sleep 0.3
check check > "$t/5.out" 2>&1; rc=$?
if [ $rc = 1 ] && grep -q '^WARN .*no certificate could be read' "$t/5.out"; then ok "5 nothing listening: exit 1, no certificate could be read"; else bad "5 rc=$rc $(cat "$t/5.out")"; fi

# 6
mv "$t/work/opnsense-backup.json" "$t/settings.away"
check check > "$t/6a.out" 2>&1; rca=$?
echo '{"host": "bad host;x"}' > "$t/work/opnsense-backup.json"
check check > "$t/6b.out" 2>&1; rcb=$?
if [ $rca = 1 ] && [ $rcb = 1 ] && grep -q 'is missing' "$t/6a.out" && grep -q 'not a name or an address' "$t/6b.out"; then ok "6 no settings file, or a bad host setting: exit 1 before any connection"; else bad "6 $rca/$rcb $(cat "$t/6a.out" "$t/6b.out")"; fi
mv "$t/settings.away" "$t/work/opnsense-backup.json"

# 7
rm -rf "$t/work/opnsense-cert"
check status > "$t/7a.out" 2>&1; r7a=$?
serve lab 100; check check > /dev/null 2>&1
check status > "$t/7b.out" 2>&1; r7b=$?
check bogus > /dev/null 2>&1; r7c=$?
check check extra > /dev/null 2>&1; r7e=$?
if [ $r7a = 1 ] && [ $r7b = 0 ] && grep -qE '^[0-9]{4}-.*Z opnsense-cert-check: notAfter' "$t/7b.out" && [ $r7c = 2 ] && [ $r7e = 2 ]; then
  ok "7 status: none yet exits 1, then prints the saved line; other arguments exit 2"; else bad "7 $r7a $r7b $r7c $r7e $(cat "$t/7a.out" "$t/7b.out")"; fi

# 8
cat "$t"/[1-7]*.out > "$t/all.out"
if grep -qi 'localhost' "$t/all.out"; then bad "8 the host's name was printed"; else ok "8 no host name in anything printed"; fi
exit "$fail"
