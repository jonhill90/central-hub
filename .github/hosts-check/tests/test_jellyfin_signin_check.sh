#!/usr/bin/env bash
# roles/k8s_identity/files/jellyfin-signin-check.py against a stand-in for Keycloak and Jellyfin (plain HTTP on localhost,
# fake values; the stand-in follows the plugin's flow as read in jellyfin-plugin-sso 5.1.1: start, redirect, state page, Auth).
#   1. The whole flow: all seven steps pass.
#   2. The password alone signing in fails step 3, and the run stops.
#   3. Jellyfin refusing the code (no state in the page) fails step 5.
#   4. A session for a user without the admin policy, when admin is expected, fails step 7.
#   5. A missing credentials file, a file others can read, and a file without a field are refused (exit 2) before any request.
#   6. The password, the seed, the state and the token never show in the output.
#   7. A start link that holds only request_uri, which Keycloak answers with a redirect to its login-actions page (the plugin's
#      pushed authorization request, measured on prod on 2026-11-19), still passes all seven steps; a redirect anywhere
#      else fails step 2.
# Usage: .github/hosts-check/tests/test_jellyfin_signin_check.sh   (needs python3)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
srv=
trap '[[ -n $srv ]] && kill "$srv" 2>/dev/null; rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
check=$root/hosts/ansible/roles/k8s_identity/files/jellyfin-signin-check.py
seed=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP
port=$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
cat > "$t/server.py" <<'PY'
import base64, hashlib, hmac, http.server, json, struct, sys, time, urllib.parse
port, mode, seed = int(sys.argv[1]), sys.argv[2], sys.argv[3]
KC, JF = "http://kc.invalid:%d" % port, "http://jf.invalid:%d" % port
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
    def do_GET(self):
        p = self.path
        if p.startswith("/sso/OID/start/keycloak"):
            return self.send(302, loc=KC + "/realms/lab/protocol/openid-connect/auth?client_id=jellyfin&response_type=code")
        if p.startswith("/realms/lab/protocol/openid-connect/auth"):
            if mode == "par": return self.send(302, loc=KC + "/realms/lab/login-actions/authenticate?client_id=jellyfin&tab_id=t")
            if mode == "parelsewhere": return self.send(302, loc="http://evil.invalid:%d/login" % port)
            return self.send(200, '<form action="/login?x=1&amp;y=2" method="post"><input name="username"><input name="password"></form>')
        if p.startswith("/realms/lab/login-actions/authenticate"):
            return self.send(200, '<form action="/login?x=1&amp;y=2" method="post"><input name="username"><input name="password"></form>')
        if p.startswith("/sso/OID/redirect/keycloak"):
            if mode == "norefusal": return self.send(400, "Error logging in", ctype="text/plain")
            return self.send(200, "<script>var data = 'state-secret-value';</script>")
        if p.startswith("/Users/Me"):
            if self.headers.get("X-Emby-Token") != "token-secret-value": return self.send(401)
            admin = mode != "notadmin"
            return self.send(200, json.dumps({"Name": "u", "Policy": {"IsAdministrator": admin}}), ctype="application/json")
        self.send(404)
    def do_POST(self):
        n = int(self.headers["Content-Length"]); raw = self.rfile.read(n).decode()
        if self.path.startswith("/sso/OID/Auth/keycloak"):
            if json.loads(raw).get("data") != "state-secret-value": return self.send(500)
            return self.send(200, json.dumps({"AccessToken": "token-secret-value", "User": {"Name": "u"}}), ctype="application/json")
        f = urllib.parse.parse_qs(raw)
        if self.path.startswith("/login"):
            if f.get("password") != ["pw-secret-value"]: return self.send(200, "<form action='/login'>bad</form>")
            if mode == "nootp": return self.send(302, loc=JF + "/sso/OID/redirect/keycloak?code=abc")
            return self.send(200, '<form action="/otp" method="post"><input name="otp"></form>')
        if f.get("otp") in ([totp(0)], [totp(-1)], [totp(1)]):
            return self.send(302, loc=JF + "/sso/OID/redirect/keycloak?code=abc&state=s")
        self.send(200, '<form action="/otp" method="post"><input name="otp"></form>')
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
run() { # mode
  [[ -z $srv ]] || { kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null || true; }
  python3 -I "$t/server.py" "$port" "$1" "$seed" & srv=$!
  sleep 0.5
  printf '{"base":"http://kc.invalid:%s","jellyfin_base":"http://jf.invalid:%s","realm":"lab","provider":"keycloak","user":"u","password":"pw-secret-value","seed":"%s","address":"127.0.0.1","verify":true,"expect_admin":true}' "$port" "$port" "$seed" > "$t/creds.json"
  chmod 600 "$t/creds.json"
  python3 -I "$check" "$t/creds.json" > "$t/out" 2>&1 && rc=0 || rc=$?
}
run normal
[[ $rc -eq 0 && $(grep -c ' ok$' "$t/out") -eq 7 ]] && ok "1. the whole flow: seven steps pass" || bad "1. $(cat "$t/out")"
cp "$t/out" "$t/out-normal"
run nootp
[[ $rc -ne 0 ]] && grep -q '^3 password only: HTTP 302 FAIL' "$t/out" && ! grep -q '^4 ' "$t/out" && ok "2. the password alone signing in fails step 3 and stops" || bad "2. $(cat "$t/out")"
run norefusal
[[ $rc -ne 0 ]] && grep -q '^5 jellyfin callback: HTTP 400 FAIL' "$t/out" && ok "3. Jellyfin refusing the code fails step 5" || bad "3. $(cat "$t/out")"
run notadmin
[[ $rc -ne 0 ]] && grep -q '^7 who am i: HTTP 200 FAIL: IsAdministrator is false, expected true' "$t/out" && ok "4. no admin policy, admin expected, fails step 7" || bad "4. $(cat "$t/out")"
python3 -I "$check" "$t/none.json" > "$t/out-missing" 2>&1 && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q '^refused: the credentials file is missing' "$t/out-missing" && ok "5a. a missing file is refused" || bad "5a. rc=$rc $(cat "$t/out-missing")"
chmod 644 "$t/creds.json"
python3 -I "$check" "$t/creds.json" > "$t/out-open" 2>&1 && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q '^refused: the credentials file must be' "$t/out-open" && ok "5b. a file others can read is refused" || bad "5b. rc=$rc $(cat "$t/out-open")"
printf '{"base":"x"}' > "$t/short.json"; chmod 600 "$t/short.json"
python3 -I "$check" "$t/short.json" > "$t/out-short" 2>&1 && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q '^refused: the credentials file lacks: jellyfin_base' "$t/out-short" && ok "5c. a file without a field is refused" || bad "5c. rc=$rc $(cat "$t/out-short")"
run par
[[ $rc -eq 0 && $(grep -c ' ok$' "$t/out") -eq 7 ]] && ok "7a. a pushed authorization request's redirect to login-actions is followed: seven steps pass" || bad "7a. $(cat "$t/out")"
run parelsewhere
[[ $rc -ne 0 ]] && grep -q '^2 login page: HTTP 302 FAIL: no login form' "$t/out" && ok "7b. a redirect to any other host is not followed: step 2 fails" || bad "7b. $(cat "$t/out")"
if ! cat "$t"/out* | grep -Eq 'pw-secret-value|state-secret-value|token-secret-value|JBSWY3DP'; then ok "6. no secret value in the output"; else bad "6. a secret value showed"; fi
exit "$fail"
