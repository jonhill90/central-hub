#!/usr/bin/env python3
"""The box side of playbooks/k8s-openbao-refresh.yml (openbao_refresh_from: box).

Signs in as the store's admin AppRole from the agent box, over the store's admin address (D-0062), writes each policy
whose text differs from the one given, binds role admin to the box's /32, reads the role back and revokes its token.
The TLS connection goes to the admin address and is checked as the store's name against the CA file, as
secrets-store.sh's curl --resolve does.

  python3 -I openbao-refresh.py <admin address> <store name> <CA file> <role-id file> <secret-id file> <box /32> < policies.json

policies.json maps each policy name to its text (no secret). The IDs are read from their files and the token stays in
memory; none is printed. Output: REFRESH lines, and role admin's settings between REFRESH-ROLE-BEGIN and -END (a role
read holds no role ID or secret ID). Exit 0 only after `REFRESH: done`.
"""
import http.client
import json
import os
import socket
import ssl
import sys


def main():
    addr, name, ca, rid_file, sid_file, cidr = sys.argv[1:7]
    texts = json.load(sys.stdin)
    ctx = ssl.create_default_context(cafile=ca)
    # The same checks curl makes on the box's other calls to the store (secrets-store.sh): chain to this CA and the name.
    # Python 3.13 adds X.509 strict mode, which also asks for extensions curl does not, so it is left off.
    ctx.verify_flags &= ~getattr(ssl, "VERIFY_X509_STRICT", 0)
    # 443 always on the box; the offline test (test_openbao_refresh.sh) runs its stand-in store on another port.
    port = int(os.environ.get("OPENBAO_REFRESH_TEST_PORT") or 443)

    class Conn(http.client.HTTPSConnection):
        # Connect to the admin address, but check the certificate (and send SNI) as the store's name.
        def connect(self):
            sock = socket.create_connection((addr, port), timeout=30)
            self.sock = ctx.wrap_socket(sock, server_hostname=name)

    def call(method, path, body=None, token=None):
        conn = Conn(name, port, context=ctx, timeout=30)
        headers = {"Content-Type": "application/json"}
        if token:
            headers["X-Vault-Token"] = token
        try:
            conn.request(method, "/v1/" + path, body=None if body is None else json.dumps(body), headers=headers)
            resp = conn.getresponse()
            raw = resp.read()
        finally:
            conn.close()
        try:
            data = json.loads(raw) if raw.strip() else {}
        except ValueError:
            data = {}
        return resp.status, data

    def fail(msg):
        print("REFRESH: " + msg)
        sys.exit(1)

    def errors(data):
        return " ".join(str(e) for e in data.get("errors") or [])[:300] or "no error text"

    with open(rid_file) as f:
        rid = f.read().strip()
    with open(sid_file) as f:
        sid = f.read().strip()
    try:
        status, data = call("POST", "auth/approle/login", {"role_id": rid, "secret_id": sid})
    except (OSError, ssl.SSLError) as e:
        fail("no answer from the store on its admin address: %s" % type(e).__name__)
    if status != 200 or not (data.get("auth") or {}).get("client_token"):
        fail("admin login from the box failed (%d): %s" % (status, errors(data)))
    token = data["auth"]["client_token"]
    try:
        changed = []
        for pname, want in texts.items():
            status, data = call("GET", "sys/policies/acl/" + pname, token=token)
            have = (data.get("data") or {}).get("policy") if status == 200 else None
            if have is not None and have.rstrip("\n") == want.rstrip("\n"):
                continue
            status, data = call("PUT", "sys/policies/acl/" + pname, {"policy": want.rstrip("\n") + "\n"}, token=token)
            if status not in (200, 204):
                fail("writing policy %s failed (%d): %s" % (pname, status, errors(data)))
            status, data = call("GET", "sys/policies/acl/" + pname, token=token)
            if status != 200 or (data.get("data") or {}).get("policy", "").rstrip("\n") != want.rstrip("\n"):
                fail("policy %s reads back different after its write" % pname)
            changed.append(pname)
        status, data = call("POST", "auth/approle/role/admin",
                            {"secret_id_bound_cidrs": [cidr], "token_bound_cidrs": [cidr]}, token=token)
        if status not in (200, 204):
            fail("binding role admin failed (%d): %s" % (status, errors(data)))
        status, data = call("GET", "auth/approle/role/admin", token=token)
        if status != 200:
            fail("reading role admin failed (%d): %s" % (status, errors(data)))
        print("REFRESH: policies changed: " + (" ".join(changed) or "none"))
        print("REFRESH-ROLE-BEGIN")
        print(json.dumps({"data": data.get("data") or {}}))
        print("REFRESH-ROLE-END")
        print("REFRESH: done")
    finally:
        try:
            call("POST", "auth/token/revoke-self", {}, token=token)
        except (OSError, ssl.SSLError):
            pass


if __name__ == "__main__":
    main()
