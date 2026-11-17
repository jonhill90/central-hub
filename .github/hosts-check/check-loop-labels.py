#!/usr/bin/env python3
"""A looped task of the agent_box role that writes a file at a path made from its loop item must label each item with
that same path (loop_control: label:). box-apply (hosts/ansible/roles/agent_box/files/box-apply.py, touched_paths)
reads the label to name a file that is not on the box yet, which a check run gives no path for; without it an approved
limit apply that adds the file stops ("did not name"). Usage: check-loop-labels.py <the role's tasks folder>."""
import glob
import os
import sys

import yaml

WRITERS = ("copy", "template", "get_url", "file")
MODS = {m: (m, "ansible.builtin." + m, "ansible.legacy." + m) for m in WRITERS}


def tasks_in(items):
    for t in items or []:
        if not isinstance(t, dict):
            continue
        yield t
        for k in ("block", "rescue", "always"):
            yield from tasks_in(t.get(k))


def target(t):
    for m in WRITERS:
        for key in MODS[m]:
            args = t.get(key)
            if not isinstance(args, dict):
                continue
            if m == "file" and args.get("state") not in ("link", "touch", "file", "hard"):
                continue
            return args.get("dest") or args.get("path")
    return None


def main(folder):
    bad = []
    for path in sorted(glob.glob(os.path.join(folder, "*.yml"))):
        for t in tasks_in(yaml.safe_load(open(path))):
            dest = target(t)
            if not isinstance(dest, str) or "item" not in dest or "loop" not in t:
                continue
            label = (t.get("loop_control") or {}).get("label")
            if label != dest:
                bad.append(f"{path}: {t.get('name', '?')}: the label is {label!r}, the destination is {dest!r}")
    for b in bad:
        print("loop label: " + b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
