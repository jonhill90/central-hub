#!/usr/bin/env python3
"""Print one client of a rendered KeycloakRealmImport as the JSON Keycloak's admin API takes.

Every ${KEY} in the client is replaced by the environment variable KEY, the way the operator
replaces it from the realm's placeholders; a key with no variable is an error, so no client ever
gets a literal "${...}" as its secret.

With --check as the third argument nothing is printed but "client <id>: ok" when the client is
there and every key has a variable; a failure prints the same reason as without it. The reason
never holds a secret, so a task that runs --check can show it where the JSON task has no_log.

Usage: client-json.py <rendered realm.yaml> <clientId> [--check]
"""
import json
import os
import re
import sys

import yaml


def main(src: str, client_id: str, check: bool = False) -> int:
    with open(src, encoding="utf-8") as f:
        clients = yaml.safe_load(f)["spec"]["realm"].get("clients", [])
    found = [c for c in clients if c["clientId"] == client_id]
    if len(found) != 1:
        print(f"client {client_id}: found {len(found)} in {src}", file=sys.stderr)
        return 1
    text = json.dumps(found[0])
    for key in sorted(set(re.findall(r"\$\{([A-Za-z0-9_]+)\}", text))):
        if key not in os.environ:
            print(f"client {client_id} uses ${{{key}}}, which is not in the environment", file=sys.stderr)
            return 1
        text = text.replace("${" + key + "}", json.dumps(os.environ[key])[1:-1])
    print(f"client {client_id}: ok" if check else text)
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3], check=sys.argv[3:] == ["--check"]))
