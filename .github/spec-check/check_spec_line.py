#!/usr/bin/env python3
"""Spec-line check: a pull request that changes a file under hosts/ names its spec or
says why it has none, on a line of its own in the PR description.

  Spec: docs/specs/2026-10-example.md        a spec that exists in the checkout
  No spec: <a reason of at least 10 characters>

Usage: check_spec_line.py --root <checkout> --body <file with the PR description> --files <file with
the changed paths, one per line>. Exit 0 = pass, 1 = fail. Standard library only. The workflow
takes this file from main, so a PR can't edit the check that judges it."""
import argparse
import os
import re
import sys

GUARDED = "hosts/"
SPEC_LINE = re.compile(r"^\s*(?:[-*]\s*)?Spec:\s*(\S.*?)\s*$", re.I)
NO_SPEC = re.compile(r"^\s*(?:[-*]\s*)?No spec:\s*(\S.*?)\s*$", re.I)
SPEC_PATH = re.compile(r"^`?(docs/specs/[A-Za-z0-9._-]+\.md)`?$")


def check(root, body, files):
    """Return a list of problems; empty means pass."""
    if not any(f.startswith(GUARDED) for f in files):
        return []
    problems = []
    for line in body.splitlines():
        m = NO_SPEC.match(line)
        if m:
            if len(m.group(1)) >= 10:
                return []
            problems.append(f"'No spec:' needs a reason of at least 10 characters, got '{m.group(1)}'")
            continue
        m = SPEC_LINE.match(line)
        if m:
            p = SPEC_PATH.match(m.group(1))
            if not p:
                problems.append(f"'Spec:' must name a file like docs/specs/2026-10-example.md, got '{m.group(1)}'")
            elif not os.path.isfile(os.path.join(root, p.group(1))):
                problems.append(f"'Spec:' names {p.group(1)}, which is not in this checkout")
            else:
                return []
    return problems or ["no 'Spec: docs/specs/<file>.md' line and no 'No spec: <reason>' line in the PR description"]


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--body", required=True)
    ap.add_argument("--files", required=True)
    a = ap.parse_args(argv)
    with open(a.body, encoding="utf-8") as f:
        body = f.read()
    with open(a.files, encoding="utf-8") as f:
        files = [l.strip() for l in f if l.strip()]
    problems = check(a.root, body, files)
    touched = sorted(f for f in files if f.startswith(GUARDED))
    if problems:
        print(f"spec-check: this PR changes {len(touched)} file(s) under {GUARDED} (first: {touched[0]})")
        for p in problems:
            print(f"spec-check: FAIL: {p}")
        return 1
    print(f"spec-check: ok ({len(touched)} file(s) under {GUARDED} changed)" if touched
          else f"spec-check: ok (nothing under {GUARDED} changed)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
