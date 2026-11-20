#!/usr/bin/env python3
"""Name the top-level sections of the tailnet policy that a saved plan would change, and nothing else.

Reads `tofu show -json <plan>` on stdin. Compares the live policy (the plan's `before`) with the rendered one
(`after`) as data: comments and trailing commas removed, so formatting, comments and key order do not count.
The provider itself compares the formatted HuJSON text, so its plan can say "1 to change" when the two mean
the same (terraform-provider-tailscale v0.29.2, tailscale/plan_modifiers.go, aclHuJSONModifier).

Prints one line: the names of the sections that differ, comma-separated, or `none`. Only section names are
printed, never their contents: the policy holds the Proxmox host's address and other private values. A name
that is not a plain word is printed as `(unnamed)`. Exit 0 on any answer it could give, 1 when the plan or a
policy cannot be read (the line then says why, without content).

Usage: tofu show -json plan.tfplan | python3 -I policy_sections.py [--attributes]

With --attributes it prints instead the names of the resource's attributes that differ (TASK-0385: a plan that says "1 to change"
with no section differing).
"""
import json
import re
import sys

PLAIN = re.compile(r"^[A-Za-z][A-Za-z0-9]{0,40}$")
ATTR = re.compile(r"^[a-z][a-z0-9_]{0,60}$")
MISSING = object()


def _strings_aware(text, on_char):
    """Walk text, copying JSON strings whole and passing every other position to on_char(text, i) -> (out, next_i)."""
    out, i, n = [], 0, len(text)
    while i < n:
        if text[i] == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        else:
            piece, i = on_char(text, i)
            out.append(piece)
    return "".join(out)


def _drop_comment(text, i):
    if text.startswith("//", i):
        j = text.find("\n", i)
        return "", len(text) if j < 0 else j
    if text.startswith("/*", i):
        j = text.find("*/", i + 2)
        return "", len(text) if j < 0 else j + 2
    return text[i], i + 1


def _drop_trailing_comma(text, i):
    if text[i] == ",":
        j = i + 1
        while j < len(text) and text[j] in " \t\r\n":
            j += 1
        if j < len(text) and text[j] in "}]":
            return "", i + 1
    return text[i], i + 1


def hujson_data(text):
    """HuJSON (JSON with comments and trailing commas) to data."""
    return json.loads(_strings_aware(_strings_aware(text, _drop_comment), _drop_trailing_comma))


def changed_sections(plan):
    acls = [r for r in plan.get("resource_changes", []) if r.get("type") == "tailscale_acl"]
    if not acls:
        return "none"
    change = acls[0].get("change", {})
    before = (change.get("before") or {}).get("acl")
    after = (change.get("after") or {}).get("acl")
    if not isinstance(before, str) or not isinstance(after, str):
        raise ValueError("the plan has no live or no rendered policy text")
    live, rendered = hujson_data(before), hujson_data(after)
    if not isinstance(live, dict) or not isinstance(rendered, dict):
        raise ValueError("a policy is not an object")
    names = sorted(set(live) | set(rendered))
    differ = [k for k in names if live.get(k, MISSING) != rendered.get(k, MISSING)]
    return ", ".join(k if PLAIN.match(k) else "(unnamed)" for k in differ) or "none"


def changed_attributes(plan):
    """Names of the tailscale_acl attributes whose planned value differs from the live one, `acl` included when its text
    differs even though the data does not (the provider compares formatted text, so comments and spacing count). Names only."""
    acls = [r for r in plan.get("resource_changes", []) if r.get("type") == "tailscale_acl"]
    if not acls:
        return "none"
    change = acls[0].get("change", {})
    before, after = change.get("before") or {}, change.get("after") or {}
    names = sorted(k for k in set(before) | set(after) if before.get(k, MISSING) != after.get(k, MISSING))
    return ", ".join(k if ATTR.match(k) else "(unnamed)" for k in names) or "none"


def main():
    try:
        if "--attributes" in sys.argv[1:]:
            print(changed_attributes(json.load(sys.stdin)))
            return 0
        print(changed_sections(json.load(sys.stdin)))
        return 0
    except (ValueError, KeyError, TypeError, AttributeError) as e:
        reason = "not readable" if isinstance(e, json.JSONDecodeError) else str(e) if isinstance(e, ValueError) else "not readable"
        print("unknown: " + reason)
        return 1


if __name__ == "__main__":
    sys.exit(main())
