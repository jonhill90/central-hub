#!/usr/bin/env python3
"""The runner hook's workflow allowlist matches the workflows that run on the agent box (D-0042 rule 4).

  check-hook-allowlist.py [REPO_ROOT]

1. Every workflow whose jobs run on the box (runs-on mentions central-hub-box) is in the hook's list, and every list entry
   is such a workflow that exists. A new box workflow, or a deleted one, fails until the list is updated.
2. Each listed hash is the sha256 of the file in this checkout, so an edit to a box workflow without the new hash fails.
3. No box workflow has a `uses:` step: a third-party or reusable action is code the file's hash does not pin.
Exit 1 with one line per problem.
"""
import glob
import hashlib
import os
import re
import sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
hook = os.path.join(root, "hosts/ansible/roles/agent_box/files/runner-job-started.sh")
problems = []
listed = dict((m.group(2), m.group(1)) for m in re.finditer(r'^\s+"([0-9a-f]{64}) (\.github/workflows/[^"\s]+)"', open(hook).read(), re.M))
retired = re.findall(r'^\s+"(\.github/workflows/[^"\s]+)"\s*$', re.sub(r'(?s)^.*?retired=\(', '', open(hook).read(), count=1).split(")", 1)[0], re.M)
if not listed:
    problems.append("the hook lists no workflow (is the allowlist format changed?)")
box = []
for p in sorted(glob.glob(os.path.join(root, ".github/workflows/*.y*ml"))):
    text = open(p, "rb").read().decode()
    rel = os.path.relpath(p, root)
    if re.search(r"runs-on:.*central-hub-box", text):
        box.append(rel)
        if re.search(r"^\s*-?\s*uses:", text, re.M):
            problems.append("%s runs on the box and has a uses: step; an action is not pinned by the file's hash" % rel)
for rel in box:
    if rel in retired:
        if rel in listed:
            problems.append("%s is both listed and retired" % rel)
    elif rel not in listed:
        problems.append("%s runs on the box but is not in the hook's list" % rel)
    elif hashlib.sha256(open(os.path.join(root, rel), "rb").read()).hexdigest() != listed[rel]:
        problems.append("%s changed: the hook's list holds a different sha256" % rel)
for rel in listed:
    if rel not in box:
        problems.append("%s is in the hook's list but is not a workflow that runs on the box" % rel)
for rel in retired:
    if not os.path.exists(os.path.join(root, rel)):
        problems.append("%s is in the hook's retired list but the file is gone: remove it from the list too" % rel)
for x in problems:
    print("hook allowlist: " + x)
sys.exit(1 if problems else 0)
