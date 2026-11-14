#!/usr/bin/env bash
# Role proxmox_sso (sign-in to Proxmox through Keycloak) against stand-ins: pveum and pvesh that keep their
# state in a JSON file, and a local HTTPS server with Keycloak's discovery document. Fake values only.
#   1. A check run changes nothing.
#   2. A first run makes the two groups, their ACLs on /, the realm (every setting, the secret as client key),
#      the /etc/hosts line, and passes the sign-in link proof.
#   3. A second run changes nothing.
#   4. A new secret in the values file changes the realm, and nothing else.
#   5. The secret never shows in the output.
#   6. A realm made with another username claim stops the run.
#   7. A sign-in link with the wrong redirect fails the proof.
# Usage: .github/hosts-check/tests/test_proxmox_sso.sh   (needs ansible-playbook, openssl, python3)
set -euo pipefail
# shellcheck disable=SC2015  # ok/bad never fail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
srv=
trap '[[ -n $srv ]] && kill "$srv" 2>/dev/null; rm -rf "$t"' EXIT
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fail=0

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost -addext subjectAltName=DNS:localhost \
  -keyout "$t/key.pem" -out "$t/cert.pem" 2>/dev/null
port=$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
issuer=https://localhost:$port/realms/lab
cat > "$t/server.py" <<'PY'
import http.server, json, ssl, sys
port, issuer, cert, key = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/realms/lab/.well-known/openid-configuration":
            self.send_response(404); self.end_headers(); return
        body = json.dumps({"issuer": issuer, "authorization_endpoint": issuer + "/protocol/openid-connect/auth"}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", port), H)
c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); c.load_cert_chain(cert, key)
s.socket = c.wrap_socket(s.socket, server_side=True)
s.serve_forever()
PY
python3 -I "$t/server.py" "$port" "$issuer" "$t/cert.pem" "$t/key.pem" & srv=$!

# pveum and pvesh: one script, state in $t/pve.json. Only the calls the role makes.
mkdir -p "$t/bin"
cat > "$t/bin/pve" <<'PY'
#!/usr/bin/env python3
import json, os, sys, urllib.parse
f = os.environ["PVE_STATE"]
st = json.load(open(f)) if os.path.exists(f) else {"groups": [], "acls": [], "realms": {}}
tool, a = os.path.basename(sys.argv[0]), sys.argv[1:]
def opts(args):
    d = {}
    for i in range(0, len(args), 2):
        d[args[i].lstrip("-")] = args[i + 1]
    return d
def save(): json.dump(st, open(f, "w"))
if tool == "pveum" and a[:2] == ["group", "list"]:
    print(json.dumps([{"groupid": g} for g in st["groups"]]))
elif tool == "pveum" and a[:2] == ["group", "add"]:
    st["groups"].append(a[2]); save()
elif tool == "pveum" and a[:2] == ["acl", "list"]:
    print(json.dumps(st["acls"]))
elif tool == "pveum" and a[:2] == ["acl", "modify"]:
    o = opts(a[3:]); st["acls"].append({"path": a[2], "type": "group", "ugid": o["groups"], "roleid": o["roles"], "propagate": 1}); save()
elif tool == "pveum" and a[:2] == ["realm", "list"]:
    print(json.dumps([{"realm": "pam", "type": "pam"}, {"realm": "pve", "type": "pve"}] + [{"realm": r, "type": "openid"} for r in st["realms"]]))
elif tool == "pveum" and a[:2] == ["realm", "add"]:
    st["realms"][a[2]] = {k: (int(v) if v in ("0", "1") else v) for k, v in opts(a[3:]).items()}; save()
elif tool == "pveum" and a[:2] == ["realm", "modify"]:
    st["realms"][a[2]].update({k: (int(v) if v in ("0", "1") else v) for k, v in opts(a[3:]).items()}); save()
elif tool == "pvesh" and a[0] == "get" and a[1].startswith("/access/domains/"):
    print(json.dumps(dict(st["realms"][a[1].rsplit("/", 1)[1]], digest="x")))
elif tool == "pvesh" and a[:2] == ["create", "/access/openid/auth-url"]:
    o = opts(a[2:-2]); r = st["realms"][o["realm"]]
    redirect = os.environ.get("PVE_BAD_REDIRECT") or o["redirect-url"]
    q = urllib.parse.urlencode({"response_type": "code", "client_id": r["client-id"], "state": "s", "redirect_uri": redirect, "scope": "openid email profile"})
    print(json.dumps(r["issuer-url"] + "/protocol/openid-connect/auth?" + q))
else:
    sys.exit("stand-in: unknown call " + " ".join(sys.argv))
PY
chmod +x "$t/bin/pve"; ln -s pve "$t/bin/pveum"; ln -s pve "$t/bin/pvesh"

secret1=SECRETONE$(printf 'a%.0s' {1..40})
secret2=SECRETTWO$(printf 'b%.0s' {1..40})
printf 'GRAFANA_CLIENT_SECRET=x\nPROXMOX_CLIENT_SECRET=%s\n' "$secret1" > "$t/identity.env"
printf '127.0.0.1 localhost\n' > "$t/hosts"
cat > "$t/play.yml" <<EOF
- name: proxmox_sso test
  hosts: localhost
  gather_facts: false
  vars:
    proxmox_sso_issuer: "$issuer"
    proxmox_sso_ui_names: [pve.example.test]
    proxmox_sso_values_file: "$t/identity.env"
    proxmox_sso_hosts_file: "$t/hosts"
    proxmox_sso_address: 192.0.2.10
  roles:
    - role: proxmox_sso
EOF
for _ in $(seq 1 50); do curl -s --cacert "$t/cert.pem" -o /dev/null "$issuer/.well-known/openid-configuration" && break; sleep 0.1; done
run() { (cd "$root/hosts/ansible" && PVE_STATE=$t/pve.json PATH=$t/bin:$PATH SSL_CERT_FILE=$t/cert.pem ANSIBLE_CONFIG=ansible.cfg \
  ansible-playbook -i localhost, -c local "$t/play.yml" "$@" 2>&1) || true; }
changed() { grep -o 'changed=[0-9]*' <<<"$1" | tail -1 | cut -d= -f2; }
q() { python3 -I -c "import json,sys; s = json.load(open('$t/pve.json')); print(($1))"; }

out=$(run --check)
[[ ! -e $t/pve.json ]] && ! grep -q proxmox_sso "$t/hosts" && ok "1. a check run changes nothing" || bad "1: $out"
out=$(run); echo "$out" > "$t/out-all"
if grep -q 'failed=0' <<<"$out" \
   && [[ $(q 'sorted(s["groups"])') == "['lab-admins-sso', 'lab-viewers-sso']" ]] \
   && [[ $(q 'sorted((a["ugid"], a["roleid"], a["path"]) for a in s["acls"])') == "[('lab-admins-sso', 'Administrator', '/'), ('lab-viewers-sso', 'PVEAuditor', '/')]" ]] \
   && [[ $(q 's["realms"]["sso"]["type"], s["realms"]["sso"]["issuer-url"], s["realms"]["sso"]["client-id"], s["realms"]["sso"]["username-claim"], s["realms"]["sso"]["autocreate"], s["realms"]["sso"]["groups-claim"], s["realms"]["sso"]["groups-overwrite"], s["realms"]["sso"]["default"]') \
        == "('openid', '$issuer', 'proxmox', 'username', 1, 'groups', 1, 1)" ]] \
   && [[ $(q 's["realms"]["sso"]["client-key"]') == "$secret1" ]] \
   && grep -qx '192.0.2.10 localhost  # central-hub proxmox_sso' "$t/hosts"; then
  ok "2. a first run makes the groups, ACLs, realm and hosts line, and the proof passes"
else bad "2: $out"; fi
out=$(run); echo "$out" >> "$t/out-all"
[[ $(changed "$out") == 0 ]] && grep -q 'failed=0' <<<"$out" && ok "3. a second run changes nothing" || bad "3: $out"
sed -i.bak "s/^PROXMOX_CLIENT_SECRET=.*/PROXMOX_CLIENT_SECRET=$secret2/" "$t/identity.env"
out=$(run); echo "$out" >> "$t/out-all"
[[ $(changed "$out") == 1 ]] && [[ $(q 's["realms"]["sso"]["client-key"]') == "$secret2" ]] && grep -q 'changed comment' <<<"$out" \
  && ok "4. a new secret changes the realm only" || bad "4: $out"
! grep -q -e "$secret1" -e "$secret2" "$t/out-all" && ok "5. the secret never shows in the output" || bad "5. a secret showed"
python3 -I -c "import json; f='$t/pve.json'; s = json.load(open(f)); s['realms']['sso']['username-claim'] = 'email'; json.dump(s, open(f, 'w'))"
out=$(run)
grep -q 'builds user names from another claim' <<<"$out" && ok "6. another username claim stops the run" || bad "6: $out"
python3 -I -c "import json; f='$t/pve.json'; s = json.load(open(f)); s['realms']['sso']['username-claim'] = 'username'; json.dump(s, open(f, 'w'))"
out=$(PVE_BAD_REDIRECT=https://elsewhere.example.test run)
grep -q "sign-in link is not what Keycloak and the client expect" <<<"$out" && ok "7. a wrong redirect fails the proof" || bad "7: $out"

[[ $fail == 0 ]] || { cat "$t/pve.json" "$t/hosts"; exit 1; }
echo "proxmox_sso: all checks passed"
