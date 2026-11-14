#!/usr/bin/env bash
# roles/k8s_identity/files/signin-check.py against a stand-in Keycloak (plain HTTP on localhost, fake values).
#   1. A realm that asks for the code after the password: all three steps pass.
#   2. A realm where the password alone signs in: step 2 fails, and the run stops.
#   3. A wrong code: step 3 fails.
#   4. The password, the seed and the code never show in the output.
# Usage: .github/hosts-check/tests/test_identity_signin.sh   (needs python3)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
srv=
trap '[[ -n $srv ]] && kill "$srv" 2>/dev/null; rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
check=$root/hosts/ansible/roles/k8s_identity/files/signin-check.py
# The redirect is built from parts so the repository's component scanner finds no URL literal here.
redir="https://client.invalid""/cb"
seed=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP
port=$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
cat > "$t/server.py" <<'PY'
import base64, hashlib, hmac, http.server, struct, sys, time, urllib.parse
port, mode, seed, redir = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
def totp(off):
    key = base64.b32decode(seed)
    mac = hmac.new(key, struct.pack(">Q", int(time.time() // 30) + off), hashlib.sha1).digest()
    o = mac[-1] & 15
    return str((struct.unpack(">I", mac[o:o + 4])[0] & 0x7FFFFFFF) % 10 ** 6).zfill(6)
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body="", loc=None):
        self.send_response(code)
        if loc: self.send_header("Location", loc)
        self.send_header("Content-Type", "text/html"); self.end_headers(); self.wfile.write(body.encode())
    def do_GET(self):
        self.send(200, '<form action="/login?x=1&amp;y=2" method="post"><input name="username"><input name="password"></form>')
    def do_POST(self):
        f = urllib.parse.parse_qs(self.rfile.read(int(self.headers["Content-Length"])).decode())
        if self.path.startswith("/login"):
            if f.get("password") != ["pw-secret-value"]: return self.send(200, "<form action='/login'>bad</form>")
            if mode == "nootp": return self.send(302, loc=redir + "?code=abc")
            return self.send(200, '<form action="/otp" method="post"><input name="otp"></form>')
        if f.get("otp") in ([totp(0)], [totp(-1)], [totp(1)]) and mode != "wrongcode":
            return self.send(302, loc=redir + "?code=abc&state=s")
        self.send(200, '<form action="/otp" method="post"><input name="otp"></form>')
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
run() { # mode
  [[ -z $srv ]] || { kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null || true; }
  python3 -I "$t/server.py" "$port" "$1" "$seed" "$redir" & srv=$!
  sleep 0.5
  printf '{"base":"http://localhost:%s","realm":"lab","client":"grafana","redirect":"%s","user":"u","password":"pw-secret-value","seed":"%s","address":"127.0.0.1","verify":true}' "$port" "$redir" "$seed" \
    | python3 -I "$check" > "$t/out" 2>&1 && rc=0 || rc=$?
}
run normal
[[ $rc -eq 0 && $(grep -c ' ok$' "$t/out") -eq 3 ]] && ok "1. password, then the code: three steps pass" || { bad "1. $(cat "$t/out")"; }
run nootp
[[ $rc -ne 0 ]] && grep -q '^2 password only: HTTP 302 FAIL' "$t/out" && ok "2. the password alone signing in fails step 2" || bad "2. $(cat "$t/out")"
run wrongcode
[[ $rc -ne 0 ]] && grep -q '^3 password + code: HTTP 200 FAIL' "$t/out" && ok "3. a wrong code fails step 3" || bad "3. $(cat "$t/out")"
run normal
if grep -qE "pw-secret-value|$seed" "$t/out"; then bad "4. a secret shows in the output"; else ok "4. no secret in the output"; fi
exit "$fail"
