#!/usr/bin/env python3
"""Check a realm imported into the test Keycloak against the JSON it was imported from, through
Keycloak's own admin tool (kcadm.sh) in the container test_realm.sh started.

- every client is there, with its redirect URIs and its public or confidential type;
- every user signs in with the password from the import (kcadm logs in to realm lab as that user);
- for every user and every client, Keycloak's example ID token carries the realm's issuer, a
  `groups` claim with the user's groups and a `roles` claim with each group's realm role.

Usage: check_realm.py <lab.json>   (environment: name = the container's name)
"""
import json
import os
import subprocess
import sys

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


def check(ok, message):
    print(("ok   " if ok else "FAIL ") + message)
    if not ok:
        failures.append(message)


def main(src):
    with open(src, encoding="utf-8") as f:
        realm = json.load(f)
    role_of = {g["name"]: g["realmRoles"] for g in realm["groups"]}

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
        password = user["credentials"][0]["value"]
        rc, _, err = kcadm("config", "credentials", "--server", "http://localhost:8080",
                           "--realm", "lab", "--user", name, "--password", password,
                           config=f"/tmp/user-{name}.config")
        check(rc == 0, f"user {name} signs in with the imported password {err.strip()}".rstrip())
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
