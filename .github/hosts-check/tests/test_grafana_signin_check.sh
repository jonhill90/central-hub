#!/usr/bin/env bash
# roles/k8s_observability/files/grafana-signin-check.py against a stand-in for Keycloak and Grafana (plain HTTP on localhost,
# fake values; the stand-in follows Grafana's generic OAuth flow: /login/generic_oauth redirects to Keycloak with a state cookie,
# the same path with code and state is the callback, the grafana_session cookie, /api/user and /api/user/orgs).
#   1. The whole flow for an admin: all seven steps pass (1b, 1c: a refused code is retried in a later window, up to three tries).
#   2. The whole flow for a viewer with expect_admin false: all seven steps pass.
#   3. The password alone signing in fails step 3, and the run stops.
#   4. Grafana refusing the code (no session cookie) fails step 5.
#   5. A session that /api/user does not know fails step 6.
#   6. A viewer where admin is expected fails step 7, and an admin where a viewer is expected too.
#   7. A missing credentials file, a file others can read, and a file without a field are refused (exit 2) before any request.
#   8. The password, the seed, the state, the code and the session value never show in the output.
# Usage: .github/hosts-check/tests/test_grafana_signin_check.sh   (needs python3)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
srv=
trap '[[ -n $srv ]] && kill "$srv" 2>/dev/null; rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
check=$root/hosts/ansible/roles/k8s_observability/files/grafana-signin-check.py
seed=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP
port=$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
cat > "$t/server.py" <<'PY'
import base64, hashlib, hmac, http.server, json, struct, sys, time, urllib.parse
port, mode, seed = int(sys.argv[1]), sys.argv[2], sys.argv[3]
KC, GR = "http://kc.invalid:%d" % port, "http://graf.invalid:%d" % port
def totp(off):
    mac = hmac.new(base64.b32decode(seed), struct.pack(">Q", int(time.time() // P) + off), hashlib.sha1).digest()
    o = mac[-1] & 15
    return str((struct.unpack(">I", mac[o:o + 4])[0] & 0x7FFFFFFF) % 10 ** 6).zfill(6)
OTP, BURNED = [0], set()
P = 2 if mode == "burned" else 30
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body="", loc=None, ctype="text/html", cookie=None):
        self.send_response(code)
        if loc: self.send_header("Location", loc)
        if cookie: self.send_header("Set-Cookie", cookie)
        self.send_header("Content-Type", ctype); self.end_headers(); self.wfile.write(body.encode())
    def authed(self):
        return "grafana_session=token-secret-value" in (self.headers.get("Cookie") or "")
    def do_GET(self):
        p = self.path
        if p.startswith("/login/generic_oauth"):
            if "code=" not in p:
                return self.send(302, loc=KC + "/realms/lab/protocol/openid-connect/auth?client_id=grafana&response_type=code&code_challenge=x&state=state-secret-value",
                                 cookie="oauth_state=cookie-state; Path=/")
            if "oauth_state=cookie-state" not in (self.headers.get("Cookie") or "") or mode == "norefusal":
                return self.send(400, "Invalid state", ctype="text/plain")
            return self.send(302, loc=GR + "/", cookie="grafana_session=token-secret-value; Path=/")
        if p.startswith("/realms/lab/protocol/openid-connect/auth"):
            return self.send(200, '<form action="/login?x=1&amp;y=2" method="post"><input name="username"><input name="password"></form>')
        if p.startswith("/api/user/orgs"):
            if not self.authed(): return self.send(401, json.dumps({"message": "Unauthorized"}), ctype="application/json")
            role = "Viewer" if mode in ("viewer", "wrongrole") else "Admin"
            return self.send(200, json.dumps([{"orgId": 1, "name": "Main Org.", "role": role}]), ctype="application/json")
        if p.startswith("/api/user"):
            if not self.authed() or mode == "nosession": return self.send(401, json.dumps({"message": "Unauthorized"}), ctype="application/json")
            return self.send(200, json.dumps({"id": 2, "login": "u", "email": "u@example.invalid"}), ctype="application/json")
        self.send(404)
    def do_POST(self):
        n = int(self.headers["Content-Length"]); raw = self.rfile.read(n).decode()
        f = urllib.parse.parse_qs(raw)
        if self.path.startswith("/login"):
            if f.get("password") != ["pw-secret-value"]: return self.send(200, "<form action='/login'>bad</form>")
            if mode == "nootp": return self.send(302, loc=GR + "/login/generic_oauth?code=code-secret-value&state=state-secret-value")
            return self.send(200, '<form action="/otp" method="post"><input name="otp"></form>')
        if f.get("otp") is not None:
            OTP[0] += 1
            if mode == "burned" and OTP[0] == 1: BURNED.update([totp(0), totp(1)])  # another check used this window's and the next window's code
            if mode == "alwaysused" or f.get("otp")[0] in BURNED:  # a code Keycloak has already accepted
                return self.send(200, '<form action="/otp" method="post"><input name="otp"></form>')
        if f.get("otp") in ([totp(0)], [totp(-1)], [totp(1)]):
            return self.send(302, loc=GR + "/login/generic_oauth?code=code-secret-value&state=state-secret-value")
        self.send(200, '<form action="/otp" method="post"><input name="otp"></form>')
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
run() { # mode expect_admin
  [[ -z $srv ]] || { kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null || true; }
  python3 -I "$t/server.py" "$port" "$1" "$seed" & srv=$!
  sleep 0.5
  printf '{"base":"http://kc.invalid:%s","grafana_base":"http://graf.invalid:%s","realm":"lab","user":"u","password":"pw-secret-value","seed":"%s","address":"127.0.0.1","verify":true,"retry_wait":0.1,"expect_admin":%s}' "$port" "$port" "$seed" "${2:-true}" > "$t/creds.json"
  [[ $1 != burned ]] || sed -i 's/"retry_wait":0.1,/"retry_wait":2.1,"period":2,/' "$t/creds.json"
  chmod 600 "$t/creds.json"
  python3 -I "$check" "$t/creds.json" > "$t/out" 2>&1 && rc=0 || rc=$?
}
run normal
[[ $rc -eq 0 && $(grep -c ' ok$' "$t/out") -eq 7 ]] && ok "1. the whole flow for an admin: seven steps pass" || bad "1. $(cat "$t/out")"
run burned true
[[ $rc -eq 0 && $(grep -c ' ok$' "$t/out") -eq 7 ]] && ok "1b. a code, and the next window's, already accepted by Keycloak: the check waits for a later window and: seven steps pass" || bad "1b. rc=$rc $(cat "$t/out")"
run alwaysused true
[[ $rc -ne 0 ]] && grep -q '^4 password + code: HTTP 200 FAIL' "$t/out" && ! grep -q '^5 ' "$t/out" && ok "1c. a code refused three times fails step 4 and stops" || bad "1c. $(cat "$t/out")"
cp "$t/out" "$t/out-normal"
run viewer false
[[ $rc -eq 0 && $(grep -c ' ok$' "$t/out") -eq 7 ]] && ok "2. the whole flow for a viewer: seven steps pass" || bad "2. $(cat "$t/out")"
run nootp
[[ $rc -ne 0 ]] && grep -q '^3 password only: HTTP 302 FAIL' "$t/out" && ! grep -q '^4 ' "$t/out" && ok "3. the password alone signing in fails step 3 and stops" || bad "3. $(cat "$t/out")"
run norefusal
[[ $rc -ne 0 ]] && grep -q '^5 grafana callback: HTTP 400 FAIL' "$t/out" && ok "4. Grafana refusing the code fails step 5" || bad "4. $(cat "$t/out")"
run nosession
[[ $rc -ne 0 ]] && grep -q '^6 who am i: HTTP 401 FAIL: not logged in' "$t/out" && ok "5. a session /api/user does not know fails step 6" || bad "5. $(cat "$t/out")"
run wrongrole
[[ $rc -ne 0 ]] && grep -q '^7 role: HTTP 200 FAIL: the first organisation.s role is Viewer, expected Admin' "$t/out" && ok "6a. a viewer where admin is expected fails step 7" || bad "6a. $(cat "$t/out")"
run normal false
[[ $rc -ne 0 ]] && grep -q '^7 role: HTTP 200 FAIL: the first organisation.s role is Admin, expected Viewer' "$t/out" && ok "6b. an admin where a viewer is expected fails step 7" || bad "6b. $(cat "$t/out")"
python3 -I "$check" "$t/none.json" > "$t/out-missing" 2>&1 && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q '^refused: the credentials file is missing' "$t/out-missing" && ok "7a. a missing file is refused" || bad "7a. rc=$rc $(cat "$t/out-missing")"
chmod 644 "$t/creds.json"
python3 -I "$check" "$t/creds.json" > "$t/out-open" 2>&1 && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q '^refused: the credentials file must be' "$t/out-open" && ok "7b. a file others can read is refused" || bad "7b. rc=$rc $(cat "$t/out-open")"
printf '{"base":"x"}' > "$t/short.json"; chmod 600 "$t/short.json"
python3 -I "$check" "$t/short.json" > "$t/out-short" 2>&1 && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q '^refused: the credentials file lacks: grafana_base' "$t/out-short" && ok "7c. a file without a field is refused" || bad "7c. rc=$rc $(cat "$t/out-short")"
if ! cat "$t"/out* | grep -Eq 'pw-secret-value|state-secret-value|code-secret-value|token-secret-value|JBSWY3DP'; then ok "8. no secret value in the output"; else bad "8. a secret value showed"; fi
exit "$fail"
