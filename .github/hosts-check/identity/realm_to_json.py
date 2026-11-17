#!/usr/bin/env python3
"""Turn a rendered KeycloakRealmImport into the realm JSON Keycloak imports, the way the operator
does: every ${KEY} placeholder is replaced by the value of spec.placeholders.KEY. Here the values
are made up (test-<KEY>, and its base32 for a TOTP_ seed), so the test knows each password and secret
without any real one.

Fails when a ${KEY} in the realm has no placeholder, or a placeholder is never used: either would
mean a password or secret that Keycloak never gets, or one the role makes for nothing.

Usage: realm_to_json.py <rendered realm.yaml> <out.json>
"""
import base64
import json
import re
import sys

import yaml


def main(src: str, dest: str) -> int:
    with open(src, encoding="utf-8") as f:
        doc = yaml.safe_load(f)
    spec = doc["spec"]
    text = json.dumps(spec["realm"])
    used = set(re.findall(r"\$\{([A-Za-z0-9_]+)\}", text))
    declared = set(spec.get("placeholders", {}))
    errors = []
    for key in sorted(used - declared):
        errors.append(f"${{{key}}} is used in the realm but is not in spec.placeholders")
    for key in sorted(declared - used):
        errors.append(f"placeholder {key} is never used in the realm")
    client_ids = [c["clientId"] for c in spec["realm"].get("clients", [])]
    for cid in sorted({c for c in client_ids if client_ids.count(c) > 1}):
        errors.append(f"client {cid} is defined twice")
    if errors:
        print("\n".join(f"FAIL: {e}" for e in errors), file=sys.stderr)
        return 1
    for key in declared:
        # A TOTP seed is base32, as the role makes it; the value is still known from the key.
        value = f"test-{key}"
        if key.startswith("TOTP_"):
            value = base64.b32encode(value.encode()).decode().rstrip("=")
        text = text.replace("${" + key + "}", value)
    with open(dest, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"realm {spec['realm']['realm']}: {len(client_ids)} clients, "
          f"{len(spec['realm'].get('users', []))} users, {len(declared)} placeholders")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
