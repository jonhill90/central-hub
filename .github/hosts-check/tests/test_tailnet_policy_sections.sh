#!/usr/bin/env bash
# policy_sections.py names the tailnet policy sections a saved plan changes, compared as data, and prints no content:
#   1. the same policy with other comments, spacing, key order and trailing commas: none.
#   2. groups and externalTailnets added: those two names, sorted.
#   3. a changed address inside grants: "grants" only, and the address is not printed.
#   4. "//" and ",}" inside a string are text, not a comment or a trailing comma.
#   5. a key that is not a plain word prints as (unnamed).
#   6. a plan with no policy change: none.
#   7. a plan with no live policy text: "unknown", exit 1.
# Usage: .github/hosts-check/tests/test_tailnet_policy_sections.sh   (needs bash and python3)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
s=$root/hosts/terraform/home/tailnet-policy/policy_sections.py
fail=0
plan() { # before-policy, after-policy -> a tofu show -json shape with one tailscale_acl change
  python3 -I -c 'import json, sys
print(json.dumps({"resource_changes": [{"type": "tailscale_acl", "change": {"actions": ["update"],
  "before": {"acl": sys.argv[1]}, "after": {"acl": sys.argv[2]}}}]}))' "$1" "$2"
}
check() { # description, expected output, expected rc, plan json
  out=$(printf '%s' "$4" | python3 -I "$s"); rc=$?
  if [[ $out == "$2" && $rc -eq $3 ]]; then echo "ok   $1"; else echo "FAIL $1 (got rc=$rc: $out)"; fail=1; fi
}
live='{
  // the live policy
  "tagOwners": {"tag:a": ["autogroup:admin"],},
  "grants": [{"src": ["tag:a"], "dst": ["192.0.2.10"], "ip": ["443"]},],
}'
same='{"grants":[{"ip":["443"],"dst":["192.0.2.10"],"src":["tag:a"]}], /* reordered */ "tagOwners":{"tag:a":["autogroup:admin"]}}'
check "1. formatting only: none" "none" 0 "$(plan "$live" "$same")"
shared='{
  "groups": {"group:x-admins": ["owner@example.com"],},
  "externalTailnets": {"x": {"externalID": "T123456CNTRL", "allowIncomingConnections": false,},},
  "tagOwners": {"tag:a": ["autogroup:admin"]},
  "grants": [{"src": ["tag:a"], "dst": ["192.0.2.10"], "ip": ["443"]}],
}'
check "2. groups and externalTailnets added" "externalTailnets, groups" 0 "$(plan "$live" "$shared")"
moved='{"tagOwners": {"tag:a": ["autogroup:admin"]}, "grants": [{"src": ["tag:a"], "dst": ["192.0.2.99"], "ip": ["443"]}]}'
check "3. a changed address: the section name only" "grants" 0 "$(plan "$live" "$moved")"
s1='{"note": "a // b ,}", "tagOwners": {}}'
s2='{"note": "a // b ,}", "tagOwners": {},}'
check "4. // and ,} inside a string are text" "none" 0 "$(plan "$s1" "$s2")"
check "5. a key that is not a plain word" "(unnamed)" 0 "$(plan '{"a b": 1}' '{"a b": 2}')"
check "6. no policy change in the plan" "none" 0 '{"resource_changes": [{"type": "null_resource", "change": {}}]}'
check "7. no live policy text" "unknown: the plan has no live or no rendered policy text" 1 \
  '{"resource_changes": [{"type": "tailscale_acl", "change": {"before": null, "after": {"acl": "{}"}}}]}'
exit "$fail"
