#!/usr/bin/env python3
"""Reads for a failed dev run (hosts/rebuild-k8s.sh runner_capture_diag, and `rebuild diag` on the agent box).

  kubectl get applications.argoproj.io -o json | diag-apps.py apps
      every Argo CD application that is not Synced and Healthy: its sync and health, its health message and conditions,
      and each of its resources that is not Synced or not Healthy, with the resource's status message.
  kubectl logs ... | diag-apps.py scrub
      the lines on stdin with secrets and long token-like strings replaced.

Both modes scrub what they print: a value after password, secret, token, key, authorization, credential or bearer (quoted or
not, and as a --flag), the password in a URL's userinfo, OpenBao and Vault tokens, and any run of 40 or more base64-like
characters, become <redacted>. They read stdin only, write nothing and run no command.
"""
import json
import re
import sys

BEARER = re.compile(r"(?i)\b(bearer|basic)\s+[^\s,;\"']+")
WORDS = re.compile(r"(?i)((?:pass(?:word|wd)?|secret|token|api[_-]?key|private[_-]?key|authorization|credential)[A-Za-z0-9_-]*[\"']?\s*[=:]\s*[\"']?)[^\s,;\"']+")
FLAGS = re.compile(r"(?i)(--(?:pass(?:word|wd)?|token|secret|api[_-]?key)[A-Za-z0-9_-]*(?:=|\s+)[\"']?)[^\s,;\"']+")
USERINFO = re.compile(r"(://[^/\s:@]+:)[^@\s/]+@")
VAULT = re.compile(r"\b(?:hv[sbr]|[sbr])\.[A-Za-z0-9_-]{20,}")
LONG = re.compile(r"[A-Za-z0-9+/=_-]{40,}")


def scrub(text):
    text = BEARER.sub(r"\1 <redacted>", text)
    text = USERINFO.sub(r"\1<redacted>@", text)
    text = FLAGS.sub(r"\1<redacted>", text)
    text = WORDS.sub(r"\1<redacted>", text)
    text = VAULT.sub("<redacted>", text)
    return LONG.sub("<redacted>", text)


def one(s, n=300):
    return scrub(" ".join(str(s or "").split()))[:n]


def apps(doc):
    shown = 0
    for a in doc.get("items", []):
        st = a.get("status", {})
        sync = st.get("sync", {}).get("status", "?")
        health = st.get("health", {}).get("status", "?")
        if sync == "Synced" and health == "Healthy":
            continue
        shown += 1
        name = a.get("metadata", {}).get("name", "?")
        print(f"{name}: sync={sync} health={health} message={one(st.get('health', {}).get('message'))}")
        for c in st.get("conditions", []) or []:
            print(f"  condition {c.get('type', '?')}: {one(c.get('message'))}")
        op = st.get("operationState", {})
        if op.get("phase") not in (None, "Succeeded"):
            print(f"  operation {op.get('phase')}: {one(op.get('message'))}")
        for r in st.get("resources", []) or []:
            rs, rh = r.get("status", "?"), (r.get("health") or {}).get("status")
            if rs == "Synced" and rh in (None, "Healthy"):
                continue
            ns = r.get("namespace") or "-"
            print(f"  {r.get('kind', '?')} {ns}/{r.get('name', '?')} sync={rs} health={rh or '-'}"
                  f" {one((r.get('health') or {}).get('message'))}")
    if not shown:
        print("every application is Synced and Healthy")


def main():
    mode = sys.argv[1] if len(sys.argv) == 2 else ""
    if mode == "apps":
        try:
            doc = json.load(sys.stdin)
        except ValueError as e:
            print(f"diag-apps: the applications did not read as JSON ({e})")
            return 0
        apps(doc)
        return 0
    if mode == "scrub":
        for line in sys.stdin:
            print(scrub(line.rstrip("\n"))[:300])
        return 0
    print("usage: diag-apps.py apps|scrub  (reads stdin)", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
