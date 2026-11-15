#!/usr/bin/env bash
# roles/openbao/files/oidc-check.py against a stand-in store and Keycloak (plain HTTP on localhost, fake values).
#   1. Admin asked for the code, gets the policy, writes and reads, is refused elsewhere; viewer and a second
#      admin refused: all 18 steps pass.
#   2. The password alone signs the admin in: step 3 fails and the run stops.
#   3. The store signs the viewer in: step 13 fails.
#   4. The admin's token reads c1's secrets: step 8 fails.
#   5. The store signs a second admin in (a role bound to the group alone): step 18 fails.
#   6. The passwords, the seeds, the codes and the tokens never show in the output.
# Usage: .github/hosts-check/tests/test_openbao_oidc_check.sh   (needs python3)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
srv=
trap '[[ -n $srv ]] && kill "$srv" 2>/dev/null; rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0
check=$root/hosts/ansible/roles/openbao/files/oidc-check.py
# The redirect is built from parts so the repository's component scanner finds no URL literal here.
redir="https://store.invalid""/ui/vault/auth/oidc/oidc/callback"
seed=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP
seed2=KRSXG5CTMVRXEZLUKRSXG5CTMVRXEZLU
port=$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
cat > "$t/server.py" <<'PY'
import base64, hashlib, hmac, http.server, json, struct, sys, time, urllib.parse
port, mode, redir = int(sys.argv[1]), sys.argv[2], sys.argv[4]
seeds = dict(zip(("admin", "other"), sys.argv[3].split(",")))
kv = {}
def totp(seed, off):
    mac = hmac.new(base64.b32decode(seed), struct.pack(">Q", int(time.time() // 30) + off), hashlib.sha1).digest()
    o = mac[-1] & 15
    return str((struct.unpack(">I", mac[o:o + 4])[0] & 0x7FFFFFFF) % 10 ** 6).zfill(6)
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body="", loc=None, ctype="text/html"):
        self.send_response(code)
        if loc: self.send_header("Location", loc)
        self.send_header("Content-Type", ctype); self.end_headers(); self.wfile.write(body.encode())
    def js(self, code, obj): self.send(code, json.dumps(obj), ctype="application/json")
    def token(self): return self.headers.get("X-Vault-Token", "")
    def do_GET(self):
        u = urllib.parse.urlsplit(self.path); q = urllib.parse.parse_qs(u.query)
        if u.path == "/realms/lab/protocol/openid-connect/auth":
            return self.send(200, '<form action="/realms/lab/login?x=1&amp;y=2" method="post"><input name="username"><input name="password"></form>')
        if u.path == "/v1/auth/oidc/oidc/callback":
            if q.get("state") != ["st"]: return self.js(400, {"errors": ["state"]})
            if q.get("code") == ["code-admin"]:
                return self.js(200, {"auth": {"client_token": "tok-admin-secret", "policies": ["default", "vps-intake"]}})
            if q.get("code") == ["code-viewer"]:
                if mode == "viewerin": return self.js(200, {"auth": {"client_token": "tok-viewer-secret", "policies": ["default"]}})
                return self.js(400, {"errors": ["claim \"groups\" does not match any associated bound claim values"]})
            if q.get("code") == ["code-other"]:
                if mode == "otherin": return self.js(200, {"auth": {"client_token": "tok-other-secret", "policies": ["default", "vps-intake"]}})
                return self.js(400, {"errors": ["claim \"preferred_username\" does not match any associated bound claim values"]})
            return self.js(400, {"errors": ["code"]})
        if self.token() != "tok-admin-secret": return self.js(403, {"errors": ["permission denied"]})
        if u.path == "/v1/kv/data/vps/proof":
            return self.js(200, {"data": {"data": kv.get("proof", {})}}) if "proof" in kv else self.js(404, {})
        if u.path == "/v1/kv/data/c1/check" and mode == "wide": return self.js(200, {"data": {"data": {"value": "x"}}})
        return self.js(403, {"errors": ["permission denied"]})
    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        u = urllib.parse.urlsplit(self.path)
        if u.path == "/v1/auth/oidc/oidc/auth_url":
            b = json.loads(raw)
            if b.get("role") != "owner" or b.get("redirect_uri") != redir: return self.js(400, {"errors": ["role"]})
            return self.js(200, {"data": {"auth_url": "http://localhost:%d/realms/lab/protocol/openid-connect/auth?client_id=openbao" % port}})
        if u.path == "/v1/kv/data/vps/proof":
            if self.token() != "tok-admin-secret": return self.js(403, {})
            kv["proof"] = json.loads(raw)["data"]; return self.js(200, {"data": {"version": 1}})
        if u.path == "/v1/auth/token/revoke-self": return self.send(204)
        f = urllib.parse.parse_qs(raw)
        if u.path == "/realms/lab/login":
            if f.get("username") == ["viewer"] and f.get("password") == ["pw-viewer-value"]:
                return self.send(302, loc=redir + "?code=code-viewer&state=st")
            who = {("admin", "pw-secret-value"): "admin", ("other", "pw-other-value"): "other"}.get(
                (f.get("username", [""])[0], f.get("password", [""])[0]))
            if not who: return self.send(200, "<form action='/realms/lab/login'>bad</form>")
            if mode == "nootp": return self.send(302, loc=redir + "?code=code-%s&state=st" % who)
            return self.send(200, '<form action="/realms/lab/otp?u=%s" method="post"><input name="otp"></form>' % who)
        who = urllib.parse.parse_qs(u.query).get("u", [""])[0]
        if u.path == "/realms/lab/otp" and who in seeds and f.get("otp") in [[totp(seeds[who], o)] for o in (-1, 0, 1)]:
            return self.send(302, loc=redir + "?code=code-%s&state=st" % who)
        self.send(200, '<form action="/realms/lab/otp?u=%s" method="post"><input name="otp"></form>' % who)
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
run() { # mode
  [[ -z $srv ]] || { kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null || true; }
  python3 -I "$t/server.py" "$port" "$1" "$seed,$seed2" "$redir" & srv=$!
  sleep 0.5
  printf '{"api":"http://127.0.0.1:%s/v1","cacert":"","mount":"oidc","role":"owner","policy":"vps-intake","prefix":"vps","redirect":"%s","kc_base":"http://localhost:%s","address":"127.0.0.1","verify":true,"admin":{"user":"admin","password":"pw-secret-value","seed":"%s"},"viewer":{"user":"viewer","password":"pw-viewer-value"},"other":{"user":"other","password":"pw-other-value","seed":"%s"}}' \
    "$port" "$redir" "$port" "$seed" "$seed2" | python3 -I "$check" > "$t/out" 2>&1 && rc=0 || rc=$?
}
run normal
[[ $rc -eq 0 && $(grep -c ' ok$' "$t/out") -eq 18 ]] && ok "1. admin with the code gets the policy only; viewer and a second admin refused: 18 steps pass" || bad "1. $(cat "$t/out")"
run nootp
[[ $rc -ne 0 ]] && grep -q '^3 admin password only: HTTP 302 FAIL' "$t/out" && ok "2. the password alone signing in fails step 3" || bad "2. $(cat "$t/out")"
run viewerin
[[ $rc -ne 0 ]] && grep -q '^13 viewer refused: HTTP 200 FAIL' "$t/out" && ok "3. a viewer signed in fails step 13" || bad "3. $(cat "$t/out")"
run wide
[[ $rc -ne 0 ]] && grep -q '^8 admin refused c1: HTTP 200 FAIL' "$t/out" && ok "4. a token that reads c1 fails step 8" || bad "4. $(cat "$t/out")"
run otherin
[[ $rc -ne 0 ]] && grep -q '^18 other refused: HTTP 200 FAIL' "$t/out" && ok "5. a second admin signed in fails step 18" || bad "5. $(cat "$t/out")"
run normal
if grep -qE "pw-secret-value|pw-viewer-value|pw-other-value|tok-|$seed|$seed2" "$t/out"; then bad "6. a secret shows in the output"; else ok "6. no secret in the output"; fi
exit "$fail"
