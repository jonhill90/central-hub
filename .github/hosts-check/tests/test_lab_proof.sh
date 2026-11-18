#!/bin/bash
# lab-proof with stubs for c1-read, python3 (the DNS query) and openssl: a good run passes and prints no host name or address; a wrong DNS
# answer and a failed verification each fail the run.
set -euo pipefail
cd "$(dirname "$0")/../../.."
script=hosts/ansible/roles/agent_box/files/lab-proof.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"
echo "nameserver 192.0.2.53" > "$t/resolv.conf"
sed -e "s#^export PATH=.*#export PATH=$t/bin:/usr/bin:/bin#" -e "s#/etc/resolv.conf#$t/resolv.conf#" "$script" > "$t/lab-proof"
cat > "$t/bin/c1-read" <<'S'
#!/bin/bash
case "$*" in
  *httproutes*) printf 'grafana=grafana.example.test grafana.apps.example.test\ngrafana-redirect=g.example.test\nsso=sso.example.test\n' ;;
  *gateway*) echo "192.0.2.10 2001:db8::10" ;;
esac
S
# python3 stub: the query's name is the first argument after -c's program
cat > "$t/bin/python3" <<'S'
#!/bin/bash
name=${*: -2:1}
if [[ ${DNS_BAD:-} == 1 && $name == sso.example.test ]]; then echo 192.0.2.99; else echo 192.0.2.10; fi
S
cat > "$t/bin/openssl" <<'S'
#!/bin/bash
if [[ ${TLS_BAD:-} == 1 ]]; then echo "Verification error: certificate has expired"; else echo "Verification: OK"; fi
S
cat > "$t/bin/timeout" <<'S'
#!/bin/bash
shift; exec "$@"
S
chmod +x "$t"/bin/*
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

out=$(bash "$t/lab-proof") || true
if [[ $out == *"PASS: lab-proof: 3 names"* ]]; then ok "good run passes, 3 names, redirect skipped"; else bad "good run: $out"; fi
if grep -qE 'example|192\.0\.2' <<< "$out"; then bad "output holds a name or address"; else ok "output holds no host name or address"; fi
if out=$(DNS_BAD=1 bash "$t/lab-proof"); then bad "wrong DNS answer passed"; elif [[ $out == *"sso #1: dns=FAIL"* ]]; then ok "wrong DNS answer fails"; else bad "wrong DNS output: $out"; fi
if out=$(TLS_BAD=1 bash "$t/lab-proof"); then bad "failed verification passed"; elif [[ $out == *"FAIL: lab-proof"* ]]; then ok "failed verification fails"; else bad "tls output: $out"; fi
if bash "$t/lab-proof" extra > /dev/null 2>&1; then bad "an argument was accepted"; else ok "an argument is refused"; fi
[[ $fails -eq 0 ]]
