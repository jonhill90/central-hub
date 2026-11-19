#!/usr/bin/env bash
# playbooks/k8s-openbao-refresh.yml offline, against a stub kubectl whose `exec ... sh -s` runs the play's in-pod
# script here with a stub `bao` that keeps its policies and role admin in files:
#   1. no box CIDR, a loopback or wider one, an env other than dev or prod, or the in-cluster store off fail it before
#      any kubectl call;
#   2. a store whose snapshot policy reads dev's mark gets prod's from ConfigMap openbao-policies, and only that policy
#      is written; role admin is bound to the box's /32; it signs in, reads, writes, binds, reads back and revokes, in
#      that order, and ends with `PASS: openbao-refresh: policies changed: snapshot`;
#   3. no secret (the token, either ID) appears in any kubectl or bao argument, or in Ansible's output;
#   4. a second run over the same policies writes none and says `policies changed: none`;
#   5. a ConfigMap whose snapshot policy reads another env's mark, or lacks a policy, stops it before the exec;
#   6. a refused admin login fails with its REFRESH line and writes nothing; a role that reads back other bindings or
#      other policies fails with a FAIL line; a pod that is not Ready stops it before the ConfigMap is read.
# From the box (an admin address in the inventory), against a stand-in store over TLS (files/openbao-refresh.py):
#   7. it signs in over the admin address, checked as the store's name against the CA file, writes only `snapshot`, binds
#      role admin, reads it back and revokes, with no kubectl exec, and ends with the same PASS line; no secret in any
#      argument or in Ansible's output; a rerun writes nothing and passes;
#   8. no CA file given refuses before any kubectl call; a CA that did not sign the store's certificate, or a refused
#      login, fails with its REFRESH line and writes nothing.
# Usage: .github/hosts-check/tests/test_openbao_refresh.sh   (needs ansible-core)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
play=$root/hosts/ansible/playbooks/k8s-openbao-refresh.yml
pol=$root/hosts/kubernetes/home/c1/apps/openbao-store/policies
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

rid=0123456789abcdef0123456789abcdef0123456789abcdef
sid=fedcba9876543210fedcba9876543210fedcba9876543210
cidr=192.0.2.7/32
printf '%s' "$rid" > "$w/role-id"
printf '%s' "$sid" > "$w/secret-id"
mkdir -p "$w/bin" "$w/pod" "$w/store"

# ConfigMap openbao-policies as Argo CD renders it: the four files, snapshot.hcl with markEnv filled in.
cm() { # env [leave-out]
  python3 -I - "$pol" "$1" "${2:-}" > "$w/cm.json" <<'PY'
import json, os, sys
d, env, leave = sys.argv[1:4]
data = {}
for n in ("admin", "bootstrap", "eso-c1", "snapshot"):
    if n == leave: continue
    data[n + ".hcl"] = open(os.path.join(d, n + ".hcl")).read().replace("{{ .Values.markEnv }}", env)
print(json.dumps({"kind": "ConfigMap", "data": data}))
PY
}
# The store as prod's self-init left it: the same policies, but the snapshot policy for dev's mark.
fresh_store() {
  rm -f "$w/store/"*
  for n in admin bootstrap eso-c1 snapshot; do
    python3 -I -c 'import sys; t = open(sys.argv[1]).read().replace("{{ .Values.markEnv }}", "dev"); print(t, end="")' "$pol/$n.hcl" > "$w/store/$n"
  done
  printf '%s' '127.0.0.1/32' > "$w/store/role-cidr"
}

cat > "$w/bin/kubectl" <<EOF
#!/usr/bin/env bash
echo "kubectl \$*" >> "$w/args"
case "\$*" in
  *"get pod openbao-0"*) printf '%s' "\${READY:-true}" ;;
  *"get configmap openbao-policies -o json"*) cat "$w/cm.json" ;;
  *"exec -i openbao-0 -c openbao -- sh -s"*) PATH="$w/pod:\$PATH" sh -s ;;
  *) echo "unexpected kubectl \$*" >&2; exit 3 ;;
esac
EOF
cat > "$w/pod/bao" <<EOF
#!/usr/bin/env bash
echo "bao \$*" >> "$w/args"
echo "bao \$*" >> "$w/calls"
[ "\$BAO_ADDR" = https://127.0.0.1:8200 ] && [ "\$BAO_TLS_SERVER_NAME" = openbao.openbao.svc ] || { echo "wrong address" >&2; exit 5; }
case "\$*" in
  "write -field=token auth/approle/login -")
    cat >> "$w/stdin"; echo >> "$w/stdin"
    case \${LOGIN:-ok} in
      ok) printf 'tok-secret-1' ;;
      *) echo 'Error writing data to auth/approle/login: Code: 400. Errors: * source address "127.0.0.1" unauthorized by CIDR restrictions on the role' >&2; exit 2 ;;
    esac ;;
  "policy read "*) [ "\$BAO_TOKEN" = tok-secret-1 ] || exit 4; [ -f "$w/store/\$3" ] || exit 2; cat "$w/store/\$3"; echo ;;
  "policy write "*" -") [ "\$BAO_TOKEN" = tok-secret-1 ] || exit 4; cat > "$w/store/\$3" ;;
  "write auth/approle/role/admin secret_id_bound_cidrs=$cidr token_bound_cidrs=$cidr")
    [ "\$BAO_TOKEN" = tok-secret-1 ] || exit 4; printf '%s' "$cidr" > "$w/store/role-cidr" ;;
  "read -format=json auth/approle/role/admin")
    [ "\$BAO_TOKEN" = tok-secret-1 ] || exit 4
    c=\$(cat "$w/store/role-cidr"); p=admin
    [ "\${ROLE:-ok}" = ok ] || p=default
    printf '{\n  "data": {\n    "secret_id_bound_cidrs": ["%s"],\n    "token_bound_cidrs": ["%s"],\n    "token_policies": ["%s"],\n    "token_ttl": 900\n  }\n}\n' "\$c" "\${c%/32}" "\$p" ;;
  "token revoke -self") ;;
  *) echo "unexpected bao \$*" >&2; exit 3 ;;
esac
EOF
chmod +x "$w/bin/kubectl" "$w/pod/bao"

# The same play, aimed at the one test host.
sed 's/^  hosts: k8s_control_plane\[0\]$/  hosts: all/' "$play" > "$w/play.yml"
grep -q '^  hosts: all$' "$w/play.yml" || { echo "FAIL the play's hosts line changed"; exit 1; }
run() { # extra -e values...
  rm -f "$w/args" "$w/calls" "$w/stdin"
  (cd "$root/hosts/ansible" && PATH="$w/bin:$PATH" ANSIBLE_CONFIG=ansible.cfg ansible-playbook \
    -i "localhost," -e '{"ansible_connection":"local","ansible_become":false}' \
    -e "ansible_python_interpreter=$(command -v python3)" \
    -e k8s_gitops_source_openbao_in_cluster=true \
    -e "openbao_admin_role_id_file=$w/role-id" -e "openbao_admin_secret_id_file=$w/secret-id" \
    "$@" "$w/play.yml") > "$w/out" 2>&1
}
has() { grep -qF -- "$2" "$1"; }
writes() { grep -c "policy write\|write auth/approle/role/admin " "$w/calls" 2>/dev/null || true; }

cm prod; fresh_store
for bad_args in "-e openbao_refresh_env=prod" "-e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=127.0.0.1/32" \
  "-e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=192.0.2.7/24" "-e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=0.0.0.0/32" \
  "-e openbao_refresh_env=staging -e k8s_gitops_source_openbao_box_cidr=$cidr" "-e k8s_gitops_source_openbao_box_cidr=$cidr" \
  "-e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr -e k8s_gitops_source_openbao_in_cluster=false"; do
  # shellcheck disable=SC2086  # the -e pairs split on purpose
  run $bad_args
  if has "$w/out" "failed=1" && [ ! -s "$w/args" ]; then ok "1. refused before any kubectl call: $bad_args"; else bad "1. not refused first: $bad_args"; fi
done

cm prod; fresh_store
run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "PASS: openbao-refresh: policies changed: snapshot; role admin bound to the box's /32"; then ok "2. a first run ends with PASS, policies changed: snapshot"; else bad "2. no PASS line"; sed -n '1,80p' "$w/out"; fi
if grep -qF 'path "kv/data/prod/snapshot-mark"' "$w/store/snapshot" && ! grep -qF 'kv/data/dev/' "$w/store/snapshot" &&
  [ "$(cat "$w/store/role-cidr")" = "$cidr" ]; then ok "2. the snapshot policy now reads prod's mark, and role admin is bound to the box's /32"; else bad "2. store not refreshed"; fi
want=$'bao write -field=token auth/approle/login -\nbao policy read admin\nbao policy read bootstrap\nbao policy read eso-c1\nbao policy read snapshot\nbao policy write snapshot -\nbao policy read snapshot\nbao write auth/approle/role/admin secret_id_bound_cidrs='"$cidr"' token_bound_cidrs='"$cidr"$'\nbao read -format=json auth/approle/role/admin\nbao token revoke -self'
if [ "$(cat "$w/calls" 2>/dev/null)" = "$want" ]; then ok "2. login, reads, one write, read-back, bind, role read, revoke: in that order"; else bad "2. calls: $(tr '\n' '|' < "$w/calls")"; fi
if has "$w/stdin" "\"role_id\":\"$rid\"" && has "$w/stdin" "\"secret_id\":\"$sid\""; then ok "3. both IDs reach bao on stdin"; else bad "3. stdin body wrong"; fi
leak=0
for s in "$rid" "$sid" tok-secret-1; do
  if has "$w/args" "$s" || has "$w/out" "$s"; then leak=1; fi
done
if [ $leak -eq 0 ]; then ok "3. no secret in any kubectl or bao argument, or in Ansible's output"; else bad "3. a secret leaked into arguments or output"; fi

run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "PASS: openbao-refresh: policies changed: none" && ! grep -q "policy write" "$w/calls"; then ok "4. a second run over the same policies writes none"; else bad "4. second run wrote or failed"; fi

cm dev; fresh_store
run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "failed=1" && ! grep -q "exec" "$w/args"; then ok "5. a ConfigMap with another env's mark stops it before the exec"; else bad "5. other env's mark not refused"; fi
cm prod bootstrap
run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "failed=1" && ! grep -q "exec" "$w/args"; then ok "5. a ConfigMap missing a policy stops it before the exec"; else bad "5. missing policy not refused"; fi

cm prod; fresh_store
LOGIN=denied run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "failed=1" && has "$w/out" "REFRESH: admin login from inside the pod failed" && [ "$(writes)" = 0 ]; then ok "6. a refused admin login fails with its REFRESH line and writes nothing"; else bad "6. refused login not reported"; fi
fresh_store
ROLE=other run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "failed=1" && has "$w/out" "FAIL: openbao-refresh: role admin reads back"; then ok "6. a role that reads back other policies fails with a FAIL line"; else bad "6. bad role read-back passed"; fi
fresh_store
READY=false run -e openbao_refresh_env=prod -e k8s_gitops_source_openbao_box_cidr=$cidr
if has "$w/out" "failed=1" && ! grep -q "configmap\|exec" "$w/args"; then ok "6. a pod that is not Ready stops it before the ConfigMap is read"; else bad "6. not-Ready pod was not stopped"; fi

# 7, 8: from the box. A stand-in store: HTTPS on a free port, a certificate for bao.invalid from its own CA.
mkdir -p "$w/files" "$w/tls"
cp "$root/hosts/ansible/playbooks/files/openbao-refresh.py" "$w/files/"
mk_ca() { # dir
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$1/ca.key" -out "$1/ca.crt" -days 2 -subj /CN=test-ca >/dev/null 2>&1
}
mkdir -p "$w/tls/other"; mk_ca "$w/tls"; mk_ca "$w/tls/other"
openssl req -newkey rsa:2048 -nodes -keyout "$w/tls/srv.key" -out "$w/tls/srv.csr" -subj /CN=bao.invalid >/dev/null 2>&1
printf 'subjectAltName=DNS:bao.invalid\n' > "$w/tls/ext"
openssl x509 -req -in "$w/tls/srv.csr" -CA "$w/tls/ca.crt" -CAkey "$w/tls/ca.key" -CAcreateserial -days 2 \
  -extfile "$w/tls/ext" -out "$w/tls/srv.crt" >/dev/null 2>&1
cat > "$w/server.py" <<'PY'
import http.server, json, os, ssl, sys
w, rid, sid, port_file = sys.argv[1:5]
store = os.path.join(w, "store")
def log(line):
    with open(os.path.join(w, "calls"), "a") as f: f.write(line + "\n")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, body=None):
        raw = b"" if body is None else json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Length", str(len(raw))); self.end_headers(); self.wfile.write(raw)
    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")
    def authed(self):
        return self.headers.get("X-Vault-Token") == "tok-secret-1"
    def handle_one(self, method):
        path = self.path[len("/v1/"):]
        log("%s %s" % (method, path))
        mode = open(os.path.join(w, "mode")).read().strip() if os.path.exists(os.path.join(w, "mode")) else "ok"
        if method == "POST" and path == "auth/approle/login":
            b = self.body()
            if mode == "denied" or b.get("role_id") != rid or b.get("secret_id") != sid:
                return self.reply(400, {"errors": ['source address "198.51.100.9" unauthorized by CIDR restrictions on the role']})
            return self.reply(200, {"auth": {"client_token": "tok-secret-1"}})
        if not self.authed(): return self.reply(403, {"errors": ["permission denied"]})
        if path.startswith("sys/policies/acl/"):
            f = os.path.join(store, path.rsplit("/", 1)[1])
            if method == "GET":
                if not os.path.exists(f): return self.reply(404, {"errors": []})
                return self.reply(200, {"data": {"policy": open(f).read()}})
            open(f, "w").write(self.body()["policy"]); return self.reply(204)
        if path == "auth/approle/role/admin" and method == "POST":
            b = self.body(); open(os.path.join(store, "role-cidr"), "w").write(b["secret_id_bound_cidrs"][0]); return self.reply(204)
        if path == "auth/approle/role/admin" and method == "GET":
            c = open(os.path.join(store, "role-cidr")).read()
            return self.reply(200, {"data": {"secret_id_bound_cidrs": [c], "token_bound_cidrs": [c[:-3] if c.endswith("/32") else c], "token_policies": ["admin"]}})
        if path == "auth/token/revoke-self": return self.reply(204)
        return self.reply(404, {"errors": ["unexpected"]})
    def do_GET(self): self.handle_one("GET")
    def do_POST(self): self.handle_one("POST")
    def do_PUT(self): self.handle_one("PUT")
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(os.path.join(w, "tls", "srv.crt"), os.path.join(w, "tls", "srv.key"))
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
open(port_file, "w").write(str(srv.server_address[1]))
srv.serve_forever()
PY
rm -f "$w/port"
python3 -I "$w/server.py" "$w" "$rid" "$sid" "$w/port" 2>/dev/null &
srv_pid=$!
trap 'kill $srv_pid 2>/dev/null; rm -rf "$w"' EXIT
for _ in $(seq 50); do [ -s "$w/port" ] && break; sleep 0.1; done
export OPENBAO_REFRESH_TEST_PORT
OPENBAO_REFRESH_TEST_PORT=$(cat "$w/port")
box_args=(-e openbao_refresh_env=prod -e "k8s_gitops_source_openbao_box_cidr=$cidr" -e k8s_gitops_source_openbao_admin_address=127.0.0.1
  -e k8s_gitops_source_openbao_store_host=bao.invalid)

cm prod; fresh_store; rm -f "$w/mode"
run "${box_args[@]}" -e "openbao_refresh_ca_file=$w/tls/ca.crt"
if has "$w/out" "PASS: openbao-refresh: policies changed: snapshot; role admin bound to the box's /32"; then ok "7. from the box: PASS, policies changed: snapshot"; else bad "7. no PASS line from the box"; sed -n '1,80p' "$w/out"; fi
if grep -qF 'path "kv/data/prod/snapshot-mark"' "$w/store/snapshot" && [ "$(cat "$w/store/role-cidr")" = "$cidr" ] && ! grep -q "exec" "$w/args"; then ok "7. from the box: the snapshot policy reads prod's mark, role admin is bound, and no kubectl exec ran"; else bad "7. box run did not refresh the store"; fi
want=$'POST auth/approle/login\nGET sys/policies/acl/admin\nGET sys/policies/acl/bootstrap\nGET sys/policies/acl/eso-c1\nGET sys/policies/acl/snapshot\nPUT sys/policies/acl/snapshot\nGET sys/policies/acl/snapshot\nPOST auth/approle/role/admin\nGET auth/approle/role/admin\nPOST auth/token/revoke-self'
if [ "$(cat "$w/calls")" = "$want" ]; then ok "7. from the box: login, reads, one write, read-back, bind, role read, revoke: in that order"; else bad "7. box calls: $(tr '\n' '|' < "$w/calls")"; fi
leak=0
for s in "$rid" "$sid" tok-secret-1; do
  if has "$w/args" "$s" || has "$w/out" "$s"; then leak=1; fi
done
if [ $leak -eq 0 ]; then ok "7. from the box: no secret in any argument or in Ansible's output"; else bad "7. a secret leaked from the box run"; fi
run "${box_args[@]}" -e "openbao_refresh_ca_file=$w/tls/ca.crt"
if has "$w/out" "PASS: openbao-refresh: policies changed: none" && ! grep -q "^PUT" "$w/calls"; then ok "7. from the box: a rerun writes nothing and passes"; else bad "7. box rerun wrote or failed"; fi

fresh_store
run "${box_args[@]}"
if has "$w/out" "failed=1" && [ ! -s "$w/args" ]; then ok "8. from the box with no CA file: refused before any kubectl call"; else bad "8. no CA file was not refused first"; fi
fresh_store
run "${box_args[@]}" -e "openbao_refresh_ca_file=$w/tls/other/ca.crt"
if has "$w/out" "failed=1" && has "$w/out" "REFRESH: no answer from the store on its admin address" && [ ! -s "$w/calls" ]; then ok "8. a CA that did not sign the store's certificate: fails, nothing sent"; else bad "8. wrong CA not refused"; sed -n '1,60p' "$w/out"; fi
fresh_store; echo denied > "$w/mode"
run "${box_args[@]}" -e "openbao_refresh_ca_file=$w/tls/ca.crt"
if has "$w/out" "failed=1" && has "$w/out" "REFRESH: admin login from the box failed (400)" && has "$w/out" "on the role" && ! grep -q "^PUT\|^POST auth/approle/role" "$w/calls"; then ok "8. a refused login from the box fails with its REFRESH line and writes nothing"; else bad "8. refused box login not reported"; fi
rm -f "$w/mode"

exit $fail
