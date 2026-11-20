#!/usr/bin/env bash
# roles/k8s_gitops/files/argocd-signin-check.py against a stand-in for Keycloak and Argo CD (plain HTTP on localhost, fake
# values; the stand-in follows Argo CD's OIDC flow as the docs describe it: /auth/login with a state cookie, the callback,
# the argocd.token cookie, /api/v1/session/userinfo and account/can-i/applications/sync/*/*, resource first as account.proto maps it).
#   1. The whole flow for an admin: all seven steps pass.
#   2. The whole flow for a viewer with expect_admin false: all seven steps pass.
#   3. The password alone signing in fails step 3, and the run stops.
#   4. Argo CD refusing the code (no session cookie) fails step 5.
#   5. An admin whose groups claim lacks lab-admins fails step 6.
#   6. An admin who cannot sync fails step 7. The stand-in answers "no" on the swapped path can-i/sync/applications/*, so a script
#      that asked it would fail the admin in cases 1 and 6's pair and pass the viewer for the wrong reason.
#      The stand-in also answers "no" for a subresource without a slash, as Argo CD does for the policy object "*/*": the script
#      asked for `sync/*` and failed an admin on prod on 2026-11-20 with "sync is no, expected yes".
#   7. A missing credentials file, a file others can read, and a file without a field are refused (exit 2) before any request.
#   8. The password, the seed, the state, the code and the token never show in the output.
# Usage: .github/hosts-check/tests/test_argocd_signin_check.sh   (needs python3)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
srv=
trap '[[ -n $srv ]] && kill "$srv" 2>/dev/null; rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
check=$root/hosts/ansible/roles/k8s_gitops/files/argocd-signin-check.py
seed=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP
port=$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
cat > "$t/server.py" <<'PY'
import base64, hashlib, hmac, http.server, json, struct, sys, time, urllib.parse
port, mode, seed = int(sys.argv[1]), sys.argv[2], sys.argv[3]
KC, AR = "http://kc.invalid:%d" % port, "http://argo.invalid:%d" % port
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
        return "argocd.token=token-secret-value" in (self.headers.get("Cookie") or "")
    def do_GET(self):
        p = self.path
        if p.startswith("/auth/login"):
            return self.send(303, loc=KC + "/realms/lab/protocol/openid-connect/auth?client_id=argocd&response_type=code&code_challenge=x&state=state-secret-value",
                             cookie="argocd.oidc.state=cookie-state; Path=/auth/callback")
        if p.startswith("/realms/lab/protocol/openid-connect/auth"):
            return self.send(200, '<form action="/login?x=1&amp;y=2" method="post"><input name="username"><input name="password"></form>')
        if p.startswith("/auth/callback"):
            if "argocd.oidc.state=cookie-state" not in (self.headers.get("Cookie") or "") or mode == "norefusal":
                return self.send(400, "Invalid state", ctype="text/plain")
            return self.send(303, loc=AR + "/applications", cookie="argocd.token=token-secret-value; Path=/")
        if p.startswith("/api/v1/session/userinfo"):
            if not self.authed(): return self.send(200, json.dumps({"loggedIn": False}), ctype="application/json")
            groups = ["lab-viewers"] if mode in ("viewer", "wronggroup") else ["lab-admins"]
            return self.send(200, json.dumps({"loggedIn": True, "username": "u", "iss": KC + "/realms/lab", "groups": groups}), ctype="application/json")
        if p.startswith("/api/v1/account/can-i/sync/applications/"):  # resource and action swapped: Argo CD would read "sync" as the resource
            return self.send(200, json.dumps({"value": "no"}), ctype="application/json")
        if p.startswith("/api/v1/account/can-i/applications/sync/"):
            # Argo CD matches the subresource against the policy's object glob "*/*" (project/app), which needs a slash:
            # "*" alone answers "no" even for role:admin (rbac.go globMatchFunc, glob.Match("*/*", "*") is false).
            rest = p[len("/api/v1/account/can-i/applications/sync/"):].split("?")[0]
            yes = mode in ("normal", "norefusal", "burned") and self.authed() and "/" in rest
            return self.send(200, json.dumps({"value": "yes" if yes else "no"}), ctype="application/json")
        self.send(404)
    def do_POST(self):
        n = int(self.headers["Content-Length"]); raw = self.rfile.read(n).decode()
        f = urllib.parse.parse_qs(raw)
        if self.path.startswith("/login"):
            if f.get("password") != ["pw-secret-value"]: return self.send(200, "<form action='/login'>bad</form>")
            if mode == "nootp": return self.send(302, loc=AR + "/auth/callback?code=code-secret-value&state=state-secret-value")
            return self.send(200, '<form action="/otp" method="post"><input name="otp"></form>')
        if f.get("otp") is not None:
            OTP[0] += 1
            if mode == "burned" and OTP[0] == 1: BURNED.update([totp(0), totp(1)])  # another check used this window's and the next window's code
            if mode == "alwaysused" or f.get("otp")[0] in BURNED:  # a code Keycloak has already accepted
                return self.send(200, '<form action="/otp" method="post"><input name="otp"></form>')
        if f.get("otp") in ([totp(0)], [totp(-1)], [totp(1)]):
            return self.send(302, loc=AR + "/auth/callback?code=code-secret-value&state=state-secret-value&session_state=x")
        self.send(200, '<form action="/otp" method="post"><input name="otp"></form>')
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
run() { # mode expect_admin
  [[ -z $srv ]] || { kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null || true; }
  python3 -I "$t/server.py" "$port" "$1" "$seed" & srv=$!
  sleep 0.5
  printf '{"base":"http://kc.invalid:%s","argocd_base":"http://argo.invalid:%s","realm":"lab","user":"u","password":"pw-secret-value","seed":"%s","address":"127.0.0.1","verify":true,"retry_wait":0.1,"expect_admin":%s}' "$port" "$port" "$seed" "${2:-true}" > "$t/creds.json"
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
[[ $rc -ne 0 ]] && grep -q '^5 argo cd callback: HTTP 400 FAIL' "$t/out" && ok "4. Argo CD refusing the code fails step 5" || bad "4. $(cat "$t/out")"
run wronggroup
[[ $rc -ne 0 ]] && grep -q '^6 who am i: HTTP 200 FAIL: the groups claim lacks the expected group' "$t/out" && ok "5. an admin without lab-admins fails step 6" || bad "5. $(cat "$t/out")"
run viewer true
[[ $rc -ne 0 ]] && grep -q '^6 who am i: HTTP 200 FAIL' "$t/out" && ok "5b. a viewer where admin is expected fails step 6" || bad "5b. $(cat "$t/out")"
run nosync
[[ $rc -ne 0 ]] && grep -q '^7 rights: HTTP 200 FAIL: sync is no, expected yes' "$t/out" && ok "6. an admin who cannot sync fails step 7" || bad "6. $(cat "$t/out")"
python3 -I "$check" "$t/none.json" > "$t/out-missing" 2>&1 && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q '^refused: the credentials file is missing' "$t/out-missing" && ok "7a. a missing file is refused" || bad "7a. rc=$rc $(cat "$t/out-missing")"
chmod 644 "$t/creds.json"
python3 -I "$check" "$t/creds.json" > "$t/out-open" 2>&1 && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q '^refused: the credentials file must be' "$t/out-open" && ok "7b. a file others can read is refused" || bad "7b. rc=$rc $(cat "$t/out-open")"
printf '{"base":"x"}' > "$t/short.json"; chmod 600 "$t/short.json"
python3 -I "$check" "$t/short.json" > "$t/out-short" 2>&1 && rc=0 || rc=$?
[[ $rc -eq 2 ]] && grep -q '^refused: the credentials file lacks: argocd_base' "$t/out-short" && ok "7c. a file without a field is refused" || bad "7c. rc=$rc $(cat "$t/out-short")"
if ! cat "$t"/out* | grep -Eq 'pw-secret-value|state-secret-value|code-secret-value|token-secret-value|JBSWY3DP'; then ok "8. no secret value in the output"; else bad "8. a secret value showed"; fi
exit "$fail"
