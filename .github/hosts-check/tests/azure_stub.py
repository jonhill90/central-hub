#!/usr/bin/env python3
"""A stand-in for Entra ID's token endpoint and Microsoft Graph addKey/removeKey, for
test_backup_azure_cert.sh. It checks what the real services check and that a test can see:
every JWT's RS256 signature against a registered certificate (or, for addKey and removeKey, the
proof's), its audience, issuer and lifetime, and that a token is a bearer the stub issued.

State lives in a JSON file (argv[2]) so the test can register a certificate the way the
playbook's first upload does, and read what the stub did:
  {"keys": {keyId: base64 DER}, "tokens": [...], "calls": [...], "reject_addkey": false}
Usage: azure_stub.py <port file> <state file> <tenant> <client id> <app object id>
"""

import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.parse
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT_FILE, STATE, TENANT, CLIENT_ID, OBJECT_ID = sys.argv[1:6]


def load():
    with open(STATE) as f:
        return json.load(f)


def save(state):
    with open(STATE + ".tmp", "w") as f:
        json.dump(state, f)
    os.replace(STATE + ".tmp", STATE)


def unb64url(text):
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def verify(jwt, state):
    """Returns (claims, keyId) if the JWT is signed by a registered certificate, else raises."""
    head, body, sig = jwt.split(".")
    header, claims = json.loads(unb64url(head)), json.loads(unb64url(body))
    assert header["alg"] == "RS256", header
    for key_id, der_b64 in state["keys"].items():
        der = base64.b64decode(der_b64)
        if base64.urlsafe_b64encode(hashlib.sha1(der).digest()).rstrip(b"=").decode() != header["x5t"]:
            continue
        with tempfile.TemporaryDirectory() as tmp:
            pem = os.path.join(tmp, "c.pem")
            with open(pem, "w") as f:
                f.write("-----BEGIN CERTIFICATE-----\n" + der_b64 + "\n-----END CERTIFICATE-----\n")
            pub = os.path.join(tmp, "pub.pem")
            with open(pub, "w") as f:
                f.write(subprocess.run(["openssl", "x509", "-in", pem, "-noout", "-pubkey"],
                                       capture_output=True, text=True, check=True).stdout)
            with open(os.path.join(tmp, "sig"), "wb") as f:
                f.write(unb64url(sig))
            ok = subprocess.run(["openssl", "dgst", "-sha256", "-verify", pub, "-signature", os.path.join(tmp, "sig")],
                                input=f"{head}.{body}".encode(), capture_output=True)
            if ok.returncode != 0:
                raise ValueError("bad signature")
        now = time.time()
        if not (claims["nbf"] - 300 <= now <= claims["exp"]):
            raise ValueError("token not valid now")
        # "flaky": a just-added key is accepted, refused twice, then accepted for good, as Entra
        # ID's replicas did on c1 (2026-11-10).
        pattern = state.get("pending", {}).get(key_id)
        if pattern:
            ok = pattern.pop(0)
            save(state)
            if not ok:
                raise LookupError("certificate not registered on this replica yet")
        return claims, key_id
    raise LookupError("certificate not registered")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def answer(self, status, body=None):
        raw = json.dumps(body).encode() if body is not None else b""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        state = load()
        path = self.path
        state["calls"].append(path)
        save(state)
        try:
            if path == f"/{TENANT}/oauth2/v2.0/token":
                return self.token(state, urllib.parse.parse_qs(raw))
            if path in (f"/v1.0/applications/{OBJECT_ID}/addKey", f"/v1.0/applications/{OBJECT_ID}/removeKey"):
                bearer = self.headers.get("Authorization", "")
                if not bearer.startswith("Bearer ") or bearer[7:] not in state["tokens"]:
                    return self.answer(401, {"error": {"code": "InvalidAuthenticationToken"}})
                return self.graph(state, path.rsplit("/", 1)[1], json.loads(raw))
            return self.answer(404, {"error": "no such path", "error_description": path})
        except Exception as err:  # the test reads this
            return self.answer(400, {"error": "stub", "error_description": repr(err)})

    def token(self, state, form):
        one = {k: v[0] for k, v in form.items()}
        assert one["grant_type"] == "client_credentials" and one["client_id"] == CLIENT_ID, one
        assert one["client_assertion_type"] == "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        try:
            claims, _ = verify(one["client_assertion"], state)
        except LookupError:
            return self.answer(401, {"error": "invalid_client", "error_description":
                                     "AADSTS700027: The certificate with identifier used to sign the client assertion is not registered on application."})
        host = f"http://{self.headers['Host']}"
        assert claims["aud"] == f"{host}/{TENANT}/oauth2/v2.0/token", claims
        assert claims["iss"] == CLIENT_ID and claims["sub"] == CLIENT_ID, claims
        tok = f"tok-{uuid.uuid4()}"
        state = load()
        state["tokens"].append(tok)
        save(state)
        return self.answer(200, {"token_type": "Bearer", "expires_in": 3599, "access_token": tok})

    def graph(self, state, action, body):
        claims, _ = verify(body["proof"], state)
        assert claims["aud"] == "00000002-0000-0000-c000-000000000000", claims
        assert claims["iss"] == OBJECT_ID, claims
        assert claims["exp"] - claims["nbf"] <= 600, claims
        if action == "addKey":
            if state.get("reject_addkey"):
                return self.answer(400, {"error": {"code": "Request_BadRequest", "message": "rejected by the test"}})
            cred = body["keyCredential"]
            assert cred["type"] == "AsymmetricX509Cert" and cred["usage"] == "Verify", cred
            assert body["passwordCredential"] is None
            key_id = str(uuid.uuid4())
            state["keys"][key_id] = cred["key"]
            if state.get("flaky"):
                state.setdefault("pending", {})[key_id] = [True, False, False]
            save(state)
            return self.answer(200, {"keyId": key_id, "type": "AsymmetricX509Cert", "usage": "Verify"})
        if body["keyId"] not in state["keys"]:
            return self.answer(400, {"error": {"code": "Request_BadRequest", "message": "No credentials found to be removed."}})
        del state["keys"][body["keyId"]]
        save(state)
        return self.answer(204)


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE, "w") as f:
    f.write(str(server.server_address[1]))
server.serve_forever()
