#!/usr/bin/env bash
# The firewall's sign-in through Keycloak by the Proxmox host's guest agent (hosts/ansible/roles/opnsense_sso,
# playbooks/opnsense-sso.yml), run for real against a stand-in `qm` whose "guest" is a folder, with shims for pkg, fetch,
# sha256 and php. Test values only; no lab value, no network but a local https server for Keycloak's discovery document.
#   1. The package pin in the role equals the pin the throwaway proof uses (opnsense-test.sh).
#   2. A check run changes nothing on the guest and prints no secret.
#   3. A first real run: the package is fetched, checked against the pin and added, the script and the settings are sent in pieces of
#      at most 512 characters, the script reads the settings and deletes them, and no settings, script or package is left.
#   4. A second run changes nothing (the marker matches).
#   5. A changed secret changes the firewall once more; the marker moves.
#   6. A package that does not match its pin is not installed, and the run fails.
#   7. The secret never appears in the run's output.
# Usage: .github/hosts-check/tests/test_opnsense_sso.sh   (needs ansible-core, PyYAML, openssl, python3)
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
role=$root/hosts/ansible/roles/opnsense_sso

# 1
url_a=$(sed -n 's/^opnsense_sso_plugin_url: //p' "$role/defaults/main.yml"); sha_a=$(sed -n 's/^opnsense_sso_plugin_sha256: //p' "$role/defaults/main.yml")
url_b=$(sed -n 's/^PLUGIN_URL=//p' "$root/hosts/ansible/roles/agent_box/files/opnsense-test.sh"); sha_b=$(sed -n 's/^PLUGIN_SHA256=//p' "$root/hosts/ansible/roles/agent_box/files/opnsense-test.sh")
[ -n "$url_a" ] && [ "$url_a" = "$url_b" ] && [ "$sha_a" = "$sha_b" ] && ok "the role's package pin equals opnsense-test.sh's" || bad "the pins differ: role $url_a $sha_a, wrapper $url_b $sha_b"

# The stand-in guest: a folder. `qm guest exec` runs the command on this machine with the guest's paths mapped into the folder.
G=$t/guest; mkdir -p "$G/root" "$G/conf" "$G/bin" "$t/bin"
good_pkg=$t/os-openid-connect.pkg; echo "a test package" > "$good_pkg"
good_sha=$(sha256sum "$good_pkg" | cut -d' ' -f1)
cat > "$G/bin/fetch" <<SH
#!/bin/sh
# fetch -q -o <file> <url>: copies the test package, or a different file when the guest holds BAD_PKG.
[ -e "$G/BAD_PKG" ] && echo "not the package" > "\$3" || cp "$good_pkg" "\$3"
SH
cat > "$G/bin/sha256" <<'SH'
#!/bin/sh
sha256sum "$2" | cut -d' ' -f1
SH
cat > "$G/bin/pkg" <<SH
#!/bin/sh
case "\$1" in
  info) [ -e "$G/PKG_INSTALLED" ] ;;
  add) echo "pkg add \$2" >> "$G/log"; touch "$G/PKG_INSTALLED" ;;
esac
SH
cat > "$G/bin/php" <<SH
#!/bin/sh
# The settings script: read the settings file, delete it, and say what it did (no secret).
echo "php ran" >> "$G/log"
grep -q client_secret "\$2" || exit 1
rm -f "\$2"
echo "<name>keycloak</name>" > "$G/conf/config.xml"
echo "openidconnect server keycloak: ok"
SH
chmod +x "$G"/bin/*
cat > "$t/bin/qm" <<PY
#!/usr/bin/env python3
import json, os, subprocess, sys
G = "$G"
a = sys.argv[1:]
if a[:1] == ["agent"]:
    sys.exit(0)
i = a.index("--")
cmd = a[i + 1:]
def m(x):
    for g, r in (("/root/", G + "/root/"), ("/conf/", G + "/conf/"), ("/usr/sbin/pkg", G + "/bin/pkg"), ("/usr/bin/fetch", G + "/bin/fetch"), ("/sbin/sha256", G + "/bin/sha256")):
        x = x.replace(g, r)
    return x
cmd = [m(x) for x in cmd]
env = dict(os.environ, PATH=G + "/bin:" + os.environ["PATH"])
open(G + "/qm.log", "a").write(" ".join(cmd)[:2000].replace("\n", " ") + "\n")
p = subprocess.run(cmd, capture_output=True, text=True, env=env)
print(json.dumps({"exited": 1, "exitcode": p.returncode, "out-data": p.stdout, "err-data": p.stderr}))
PY
chmod +x "$t/bin/qm"

# Keycloak's discovery document, at a local https address with a certificate made here.
port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 2 -subj "/CN=localhost" -keyout "$t/k.key" -out "$t/k.crt" 2>/dev/null
mkdir -p "$t/www/realms/lab/.well-known"
printf '{"issuer": "https://localhost:%s/realms/lab"}' "$port" > "$t/www/realms/lab/.well-known/openid-configuration"
python3 - "$port" "$t/www" "$t/k.crt" "$t/k.key" <<'PY' &
import http.server, ssl, sys, functools
port, www, crt, key = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
class H(http.server.SimpleHTTPRequestHandler):
    extensions_map = {"": "application/json"}
h = functools.partial(H, directory=www)
s = http.server.ThreadingHTTPServer(("127.0.0.1", port), h)
c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); c.load_cert_chain(crt, key); s.socket = c.wrap_socket(s.socket, server_side=True)
s.serve_forever()
PY
pids+=($!)
for _ in $(seq 1 50); do curl -sk -o /dev/null "https://localhost:$port/" && break; sleep 0.2; done

secret1=$(openssl rand -hex 24); secret2=$(openssl rand -hex 24)
printf 'GRAFANA_CLIENT_SECRET=x\nOPNSENSE_CLIENT_SECRET=%s\n' "$secret1" > "$t/values.env"
cat > "$t/inventory.yml" <<EOF
proxmox:
  hosts:
    proxmox_host:
      ansible_connection: local
      ansible_python_interpreter: $(command -v python3)
      opnsense_sso_issuer: https://localhost:$port/realms/lab
EOF
run() { # extra args; output to $t/out
  ( cd "$root/hosts/ansible" && PATH="$t/bin:$PATH" ANSIBLE_ROLES_PATH="$root/hosts/ansible/roles" ANSIBLE_NOCOLOR=1 \
    ansible-playbook -i "$t/inventory.yml" playbooks/opnsense-sso.yml -e "opnsense_sso_values_file=$t/values.env" \
      -e opnsense_sso_validate_certs=false -e "opnsense_sso_plugin_sha256=$good_sha" "$@" ) > "$t/out" 2>&1
}
guest_state() { find "$G/root" "$G/conf" -type f ! -name config.xml | sort | sed "s|$G||" | tr '\n' ' '; }

# 2
run --check; rc=$?
if [ $rc = 0 ] && [ ! -e "$G/PKG_INSTALLED" ] && [ -z "$(guest_state)" ]; then ok "a check run changes nothing on the guest"; else bad "check run: rc $rc, state '$(guest_state)'"; tail -20 "$t/out"; fi

grep -q 'changed=1 ' "$t/out" && grep -q "would install os-openid-connect" "$t/out" && ok "a check run on a firewall without the package shows one change, saying what would be done" || { bad "check run shows no change"; tail -20 "$t/out"; }

# 3
run; rc=$?
if [ $rc = 0 ] && [ -e "$G/PKG_INSTALLED" ] && grep -q "^pkg add" "$G/log" && grep -q "^php ran" "$G/log"; then ok "first run installs the package and runs the settings script"; else bad "first run: rc $rc"; tail -30 "$t/out"; fi
left=$(guest_state)
case "$left" in "/conf/.central-hub-opnsense-sso ") ok "only the marker is left on the guest" ;; *) bad "files left on the guest: $left" ;; esac
max=$(grep -o 'printf %s [A-Za-z0-9+/=]*' "$G/qm.log" | awk '{ print length($3) }' | sort -n | tail -1)
[ "${max:-0}" -gt 0 ] && [ "$max" -le 512 ] && ok "no piece sent to the guest is over 512 characters (largest $max)" || bad "piece size: ${max:-none}"

# 4
before=$(wc -l < "$G/log"); run; rc=$?
after=$(wc -l < "$G/log")
[ $rc = 0 ] && [ "$before" = "$after" ] && ok "a second run changes nothing" || { bad "second run: rc $rc, log lines $before to $after"; tail -20 "$t/out"; }

run --check; rc=$?
[ $rc = 0 ] && grep -q 'changed=0 ' "$t/out" && ok "a check run after the apply shows no change" || { bad "check after apply: rc $rc"; tail -20 "$t/out"; }

# 5
printf 'OPNSENSE_CLIENT_SECRET=%s\n' "$secret2" > "$t/values.env"
run; rc=$?; after2=$(wc -l < "$G/log")
[ $rc = 0 ] && [ "$after2" -gt "$after" ] && ok "a changed secret runs the script again" || { bad "changed secret: rc $rc"; tail -20 "$t/out"; }

# 6
rm -f "$G/PKG_INSTALLED" "$G/conf/.central-hub-opnsense-sso"; touch "$G/BAD_PKG"
run; rc=$?
if [ $rc != 0 ] && [ ! -e "$G/PKG_INSTALLED" ]; then ok "a package that does not match its pin is not installed and the run fails"; else bad "bad package: rc $rc, installed $([ -e "$G/PKG_INSTALLED" ] && echo yes || echo no)"; fi
rm -f "$G/BAD_PKG"

# 7
if grep -q -e "$secret1" -e "$secret2" "$t/out"; then bad "a secret is in the run's output"; else ok "no secret in the run's output"; fi

exit $fail
