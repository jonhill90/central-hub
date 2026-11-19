#!/usr/bin/env bash
# roles/proxmox_sso/files/proxmox-signin-check.py against a stand-in for Keycloak and the Proxmox API (plain HTTP on
# localhost, fake values; the stand-in follows pve-manager's login flow: auth-url, the redirect back, openid/login, permissions).
#   1. The whole flow: all six steps pass.
#   2. The password alone signing in fails step 3, and the run stops.
#   3. Proxmox refusing the code fails step 5.
#   4. A session without Sys.Modify on /, when admin is expected, fails step 6.
#   5. An auth link that redirects somewhere else than the web UI fails step 1.
#   6. A missing credentials file, a file others can read, and a file without a field are refused (exit 2) before any request.
#   7. The password, the seed, the state, the code and the ticket never show in the output.
# Usage: .github/hosts-check/tests/test_proxmox_signin_check.sh   (needs python3)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
srv=
trap '[[ -n $srv ]] && kill "$srv" 2>/dev/null; rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
check=$root/hosts/ansible/roles/proxmox_sso/files/proxmox-signin-check.py
seed=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP
port=$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
cat > "$t/server.py" <<'PY'
import base64, hashlib, hmac, http.server, json, struct, sys, time, urllib.parse
port, mode, seed = int(sys.argv[1]), sys.argv[2], sys.argv[3]
KC, PVE = "http://kc.invalid:%d" % port, "http://pve.invalid:%d" % port
TICKET = "PVE:u@sso:ticket-secret-value::c2ln"
def totp(off):
    mac = hmac.new(base64.b32decode(seed), struct.pack(">Q", int(time.time() // 30) + off), hashlib.sha1).digest()
    o = mac[-1] & 15
    return str((struct.unpack(">I", mac[o:o + 4])[0] & 0x7FFFFFFF) % 10 ** 6).zfill(6)
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body="", loc=None, ctype="text/html"):
        self.send_response(code)
        if loc: self.send_header("Location", loc)
        self.send_header("Content-Type", ctype); self.end_headers(); self.wfile.write(body.encode())
    def j(self, code, data):
        self.send(code, json.dumps({"data": data}), ctype="application/json")
    def do_GET(self):
        p = self.path
        if p.startswith("/realms/lab/protocol/openid-connect/auth"):
            return self.send(200, '<form action="/login?x=1&amp;y=2" method="post"><input name="username"><input name="password"></form>')
        if p.startswith("/api2/json/access/permissions"):
            if self.headers.get("Cookie") != "PVEAuthCookie=" + urllib.parse.quote(TICKET, safe=""): return self.send(401)
            return self.j(200, {"/": {"Sys.Audit": 1, "Sys.Modify": 1} if mode != "notadmin" else {"Sys.Audit": 1}})
        self.send(404)
    def do_POST(self):
        n = int(self.headers["Content-Length"]); raw = self.rfile.read(n).decode()
        if self.path == "/api2/json/access/openid/auth-url":
            b = json.loads(raw)
            if b != {"realm": "sso", "redirect-url": PVE}: return self.send(400)
            back = "http://elsewhere.invalid" if mode == "wrongurl" else PVE
            return self.j(200, KC + "/realms/lab/protocol/openid-connect/auth?client_id=proxmox&response_type=code&redirect_uri="
                          + urllib.parse.quote(back, safe="") + "&state=state-secret-value")
        if self.path == "/api2/json/access/openid/login":
            b = json.loads(raw)
            if mode == "norefusal" or b != {"state": "state-secret-value", "code": "code-secret-value", "redirect-url": PVE}:
                return self.send(401, json.dumps({"data": None}), ctype="application/json")
            return self.j(200, {"ticket": TICKET, "username": "u@sso", "CSRFPreventionToken": "x"})
        f = urllib.parse.parse_qs(raw)
        if self.path.startswith("/login"):
            if f.get("password") != ["pw-secret-value"]: return self.send(200, "<form action='/login'>bad</form>")
            if mode == "nootp": return self.send(302, loc=PVE + "?state=state-secret-value&code=code-secret-value")
            return self.send(200, '<form action="/otp" method="post"><input name="otp"></form>')
        if f.get("otp") in ([totp(0)], [totp(-1)], [totp(1)]):
            return self.send(302, loc=PVE + "?state=state-secret-value&code=code-secret-value&iss=x")
        self.send(200, '<form action="/otp" method="post"><input name="otp"></form>')
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
run() { # mode
  [[ -z $srv ]] || { kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null || true; }
  python3 -I "$t/server.py" "$port" "$1" "$seed" & srv=$!
  sleep 0.5
  printf '{"base":"http://kc.invalid:%s","pve_base":"http://pve.invalid:%s","realm":"lab","user":"u","password":"pw-secret-value","seed":"%s","address":"127.0.0.1","verify":true,"expect_admin":true}' "$port" "$port" "$seed" > "$t/creds.json"
  chmod 600 "$t/creds.json"
  python3 -I "$check" "$t/creds.json" > "$t/out" 2>&1 && rc=0 || rc=$?
}
run normal
[[ $rc -eq 0 && $(grep -c ' ok$' "$t/out") -eq 6 ]] && ok "1. the whole flow: six steps pass" || bad "1. $(cat "$t/out")"
cp "$t/out" "$t/out-normal"
run nootp
[[ $rc -ne 0 ]] && grep -q '^3 password only: HTTP 302 FAIL' "$t/out" && ! grep -q '^4 ' "$t/out" && ok "2. the password alone signing in fails step 3 and stops" || bad "2. $(cat "$t/out")"
run norefusal
[[ $rc -ne 0 ]] && grep -q '^5 proxmox login: HTTP 401 FAIL' "$t/out" && ok "3. Proxmox refusing the code fails step 5" || bad "3. $(cat "$t/out")"
run notadmin
[[ $rc -ne 0 ]] && grep -q '^6 permissions: HTTP 200 FAIL: Sys.Modify on / is false, expected true' "$t/out" && ok "4. no Sys.Modify, admin expected, fails step 6" || bad "4. $(cat "$t/out")"
run wrongurl
[[ $rc -ne 0 ]] && grep -q '^1 auth url: HTTP 200 FAIL' "$t/out" && ! grep -q '^2 ' "$t/out" && ok "5. an auth link back to another place fails step 1" || bad "5. $(cat "$t/out")"
python3 -I "$check" "$t/none.json" > "$t/out-missing" 2>&1 && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q '^refused: the credentials file is missing' "$t/out-missing" && ok "6a. a missing file is refused" || bad "6a. rc=$rc $(cat "$t/out-missing")"
chmod 644 "$t/creds.json"
python3 -I "$check" "$t/creds.json" > "$t/out-open" 2>&1 && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q '^refused: the credentials file must be' "$t/out-open" && ok "6b. a file others can read is refused" || bad "6b. rc=$rc $(cat "$t/out-open")"
printf '{"base":"x"}' > "$t/short.json"; chmod 600 "$t/short.json"
python3 -I "$check" "$t/short.json" > "$t/out-short" 2>&1 && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q '^refused: the credentials file lacks: pve_base' "$t/out-short" && ok "6c. a file without a field is refused" || bad "6c. rc=$rc $(cat "$t/out-short")"
if ! cat "$t"/out* | grep -Eq 'pw-secret-value|state-secret-value|code-secret-value|ticket-secret-value|JBSWY3DP'; then ok "7. no secret value in the output"; else bad "7. a secret value showed"; fi
exit "$fail"
