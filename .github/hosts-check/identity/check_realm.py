#!/usr/bin/env python3
"""Check a realm imported into the test Keycloak against the JSON it was imported from, through
Keycloak's own admin tool (kcadm.sh) in the container test_realm.sh started.

- users can't change their user name (Proxmox builds its user names from it, role proxmox_sso);
- every client is there, with its redirect URIs and its public or confidential type;
- every user signs in with the password from the import, through the token endpoint's password grant;
  a user with an OTP credential (an admin) is refused without a code and signs in with the TOTP code
  from the imported seed;
- for every user and every client, Keycloak's example ID token carries the realm's issuer, a
  `groups` claim with the user's groups and a `roles` claim with each group's realm role.

Usage: check_realm.py <lab.json>   (environment: name = the container's name)
"""
import base64
import hashlib
import hmac
import json
import os
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HOST = "https://sso.example.com"
CONTAINER = os.environ["name"]
failures = []


def kcadm(*args, config="/tmp/kcadm.config"):
    out = subprocess.run(
        ["docker", "exec", CONTAINER, "/opt/keycloak/bin/kcadm.sh", *args, "--config", config],
        capture_output=True, text=True, check=False)
    return out.returncode, out.stdout, out.stderr


def get(path, *query):
    args = ["get", path, "-r", "lab"]
    for q in query:
        args += ["-q", q]
    rc, out, err = kcadm(*args)
    if rc != 0:
        raise SystemExit(f"kcadm get {path} failed: {err.strip()}")
    return json.loads(out)


def totp(seed, period=30, digits=6):
    """RFC 6238 with SHA-1, the realm's OTP policy."""
    key = base64.b32decode(seed + "=" * (-len(seed) % 8))
    mac = hmac.new(key, struct.pack(">Q", int(time.time()) // period), hashlib.sha1).digest()
    off = mac[-1] & 15
    return str((struct.unpack(">I", mac[off:off + 4])[0] & 0x7FFFFFFF) % 10 ** digits).zfill(digits)


def sign_in(name, password, code=None):
    """The password grant on realm lab's token endpoint, as admin-cli; True when a token comes back."""
    ip = subprocess.run(["docker", "inspect", "-f", "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
                         CONTAINER], capture_output=True, text=True, check=True).stdout.strip()
    form = {"grant_type": "password", "client_id": "admin-cli", "username": name, "password": password}
    if code:
        form["totp"] = code
    req = urllib.request.Request(f"http://{ip}:8080/realms/lab/protocol/openid-connect/token",
                                 data=urllib.parse.urlencode(form).encode())
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return "access_token" in json.load(r)
    except urllib.error.HTTPError:
        return False


def check(ok, message):
    print(("ok   " if ok else "FAIL ") + message)
    if not ok:
        failures.append(message)


def main(src):
    with open(src, encoding="utf-8") as f:
        realm = json.load(f)
    role_of = {g["name"]: g["realmRoles"] for g in realm["groups"]}

    rc, out, err = kcadm("get", "realms/lab")
    if rc != 0:
        raise SystemExit(f"kcadm get realms/lab failed: {err.strip()}")
    check(json.loads(out).get("editUsernameAllowed") is False, "users can't change their user name")

    clients = {}
    for want in realm["clients"]:
        found = get("clients", f"clientId={want['clientId']}")
        check(len(found) == 1, f"client {want['clientId']} exists")
        if not found:
            continue
        have = found[0]
        clients[want["clientId"]] = have["id"]
        check(sorted(have.get("redirectUris", [])) == sorted(want["redirectUris"]),
              f"client {want['clientId']} redirects only to {want['redirectUris']}")
        check(have.get("publicClient") == want["publicClient"],
              f"client {want['clientId']} publicClient={want['publicClient']}")

    for user in realm["users"]:
        name = user["username"]
        password = next(c["value"] for c in user["credentials"] if c["type"] == "password")
        otp = [c for c in user["credentials"] if c["type"] == "otp"]
        if otp:
            seed = json.loads(otp[0]["secretData"])["value"]
            check(not sign_in(name, password), f"user {name} is refused with the password alone")
            # One retry, in case the code turned over between making and sending it.
            check(sign_in(name, password, totp(seed)) or sign_in(name, password, totp(seed)),
                  f"user {name} signs in with the imported password and a TOTP code")
        else:
            check(sign_in(name, password), f"user {name} signs in with the imported password")
        found = get("users", f"username={name}", "exact=true")
        if not found:
            check(False, f"user {name} exists")
            continue
        groups = sorted(g.lstrip("/") for g in user["groups"])
        roles = sorted(r for g in groups for r in role_of[g])
        for client_id, cid in clients.items():
            token = get(f"clients/{cid}/evaluate-scopes/generate-example-id-token",
                        f"userId={found[0]['id']}", "scope=openid")
            check(token.get("iss") == f"{HOST}/realms/lab", f"{client_id} token for {name}: issuer {token.get('iss')}")
            check(sorted(token.get("groups", [])) == groups, f"{client_id} token for {name}: groups {token.get('groups')}")
            check(sorted(r for r in token.get("roles", []) if r in ("admin", "viewer")) == roles,
                  f"{client_id} token for {name}: roles {token.get('roles')}")

    if failures:
        print(f"{len(failures)} check(s) failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
