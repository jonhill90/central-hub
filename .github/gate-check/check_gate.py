#!/usr/bin/env python3
"""Activation gate checks a script can see (docs/specs/2026-10-activation-gate.md).

Item 3, no write tokens in PR code: every workflow under .github/workflows/
  - runs on no trigger that gives PR code a privileged context (pull_request_target, workflow_run,
    issue_comment, issues; AGENTS.md rule 5);
  - declares permissions at the top and in no job asks for more than read;
  - reads no secret;
  - checks out with persist-credentials: false, so no token is left in .git/config;
  - pins every action and reusable workflow to a full commit SHA.
Item 6, no image automation: no tracked file outside docs/ and .github/ asks for Argo CD Image
Updater or Flux's image automation kinds.

Usage: check_gate.py <repo root>. Prints every failure and exits 1 if there is one.
"""
import pathlib
import re
import subprocess
import sys

import yaml

BANNED_TRIGGERS = {"pull_request_target", "workflow_run", "issue_comment", "issues"}
READ_ONLY = {"read", "none"}
SHA_PIN = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")
IMAGE_AUTOMATION = re.compile(
    r"argocd-image-updater|kind:\s*(ImageUpdateAutomation|ImagePolicy|ImageRepository)\b"
)


def permission_failures(where, perms):
    if perms is None:
        return [f"{where}: no permissions block"]
    if isinstance(perms, str):
        return [] if perms == "read-all" or perms in READ_ONLY else [f"{where}: permissions: {perms}"]
    return [f"{where}: {scope}: {level}" for scope, level in perms.items() if level not in READ_ONLY]


def check_workflow(path):
    text = path.read_text()
    doc = yaml.safe_load(text)
    fails = []
    # PyYAML reads the key `on` as True.
    triggers = doc.get("on", doc.get(True))
    names = set(triggers) if isinstance(triggers, (dict, list)) else {triggers}
    fails += [f"{path}: trigger {t}" for t in sorted(names & BANNED_TRIGGERS)]
    fails += permission_failures(f"{path}: top level", doc.get("permissions"))
    if "secrets." in text:
        fails.append(f"{path}: reads a secret")
    for job_name, job in (doc.get("jobs") or {}).items():
        where = f"{path}: job {job_name}"
        if "permissions" in job:
            fails += permission_failures(where, job["permissions"])
        if "uses" in job and not job["uses"].startswith("./") and not SHA_PIN.match(job["uses"]):
            fails.append(f"{where}: reusable workflow not pinned to a SHA: {job['uses']}")
        if job.get("secrets"):
            fails.append(f"{where}: passes secrets")
        for step in job.get("steps") or []:
            uses = step.get("uses")
            if not uses or uses.startswith("./"):
                continue
            if not SHA_PIN.match(uses):
                fails.append(f"{where}: action not pinned to a SHA: {uses}")
            if uses.startswith("actions/checkout@") and (step.get("with") or {}).get("persist-credentials") is not False:
                fails.append(f"{where}: checkout without persist-credentials: false")
    return fails


def tracked(root):
    out = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True, check=True)
    return [p for p in out.stdout.decode().split("\0") if p]


def main(root):
    root = pathlib.Path(root)
    fails = []
    for path in sorted((root / ".github" / "workflows").glob("*.y*ml")):
        fails += check_workflow(path)
    for rel in tracked(root):
        if rel.startswith(("docs/", ".github/")):
            continue
        path = root / rel
        if path.suffix not in {".yml", ".yaml", ".j2", ".json"} or not path.is_file():
            continue
        if IMAGE_AUTOMATION.search(path.read_text(errors="replace")):
            fails.append(f"{rel}: image automation (Activation gate item 6)")
    for line in fails:
        print(f"FAIL: {line}", file=sys.stderr)
    if fails:
        return 1
    print("gate: items 3 and 6 pass")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
