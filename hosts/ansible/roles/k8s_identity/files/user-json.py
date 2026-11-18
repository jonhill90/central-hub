#!/usr/bin/env python3
"""Print one user of a rendered KeycloakRealmImport as the JSON Keycloak's admin API takes for a new user.

Every ${KEY} in the user (its password and its TOTP seed) is replaced by the environment variable KEY, the
way the operator replaces it from the realm's placeholders; a key with no variable is an error, so no user
ever gets a literal "${...}" as a password.

Usage: user-json.py <rendered realm.yaml> <username>
"""
import json
import os
import re
import sys

import yaml


def main(src: str, username: str) -> int:
    with open(src, encoding="utf-8") as f:
        users = yaml.safe_load(f)["spec"]["realm"].get("users", [])
    found = [u for u in users if u["username"] == username]
    if len(found) != 1:
        print(f"user {username}: found {len(found)} in {src}", file=sys.stderr)
        return 1
    text = json.dumps(found[0])
    for key in sorted(set(re.findall(r"\$\{([A-Za-z0-9_]+)\}", text))):
        if key not in os.environ:
            print(f"user {username} uses ${{{key}}}, which is not in the environment", file=sys.stderr)
            return 1
        text = text.replace("${" + key + "}", json.dumps(os.environ[key])[1:-1])
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
