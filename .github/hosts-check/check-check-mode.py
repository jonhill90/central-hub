#!/usr/bin/env python3
"""A pipeline job's check run must change nothing (D-0041 rule 4; Library plans/r1-host-job/DESIGN.md v3.1 section 7).

`check_mode: false` makes a task run for real during `--check`. For each playbook named here, every task in the
roles it runs (tasks/ and handlers/, with blocks and included roles) that sets `check_mode: false` must be either
  - a module on a read-only list (slurp, stat, assert, debug, set_fact, meta, package_facts), or
  - `command` or `shell` with `changed_when: false` and a fixed command line: no `{{ }}` in it except a value
    passed through `| quote`.
Anything else fails.

Usage: check-check-mode.py <repository root> <playbook relative to hosts/ansible> ...
"""
import os
import re
import sys

import yaml

READ_ONLY = {"slurp", "stat", "assert", "debug", "set_fact", "meta", "package_facts"}
RUNS = {"command", "shell"}
KEYWORDS = {
    "name", "when", "tags", "register", "loop", "loop_control", "with_items", "with_dict", "with_list",
    "changed_when", "failed_when", "check_mode", "become", "become_user", "delegate_to", "run_once",
    "notify", "listen", "vars", "environment", "ignore_errors", "no_log", "until", "retries", "delay",
    "args", "block", "rescue", "always", "diff", "timeout", "any_errors_fatal", "throttle", "module_defaults",
}
QUOTED = re.compile(r"\{\{[^{}]*\|\s*quote\s*\}\}")


def module_of(task):
    for k in task:
        if k not in KEYWORDS and not k.startswith("with_"):
            return k.split(".")[-1], task[k]
    return None, None


def walk(tasks, where, problems, roles_seen, root):
    for task in tasks or []:
        if not isinstance(task, dict):
            continue
        for key in ("block", "rescue", "always"):
            if key in task:
                walk(task[key], where, problems, roles_seen, root)
        mod, arg = module_of(task)
        if mod in ("include_role", "import_role") and isinstance(arg, dict):
            role(arg.get("name", ""), problems, roles_seen, root)
        if task.get("check_mode") is not False:
            continue
        label = "%s: %s" % (where, task.get("name", "(no name)"))
        if mod in READ_ONLY:
            continue
        if mod in RUNS:
            line = str(arg.get("cmd", "") if isinstance(arg, dict) else (arg or ""))
            if task.get("changed_when") is not False:
                problems.append("%s: %s with check_mode false needs changed_when: false" % (label, mod))
            elif "{{" in QUOTED.sub("", line):
                problems.append("%s: %s with check_mode false has a templated value that is not | quote" % (label, mod))
            continue
        problems.append("%s: module %s with check_mode false is not read-only" % (label, mod))


def role(name, problems, roles_seen, root):
    if not name or name in roles_seen:
        return
    roles_seen.add(name)
    base = os.path.join(root, "hosts/ansible/roles", name)
    if not os.path.isdir(base):
        problems.append("role %s not found" % name)
        return
    for sub in ("tasks", "handlers"):
        d = os.path.join(base, sub)
        for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if f.endswith((".yml", ".yaml")):
                walk(yaml.safe_load(open(os.path.join(d, f))), "%s/%s/%s" % (name, sub, f), problems, roles_seen, root)


def main():
    root, playbooks = sys.argv[1], sys.argv[2:]
    if not playbooks:
        sys.exit(__doc__)
    problems, roles_seen = [], set()
    for pb in playbooks:
        for play in yaml.safe_load(open(os.path.join(root, "hosts/ansible", pb))) or []:
            for r in play.get("roles", []):
                role(r if isinstance(r, str) else r.get("role", r.get("name", "")), problems, roles_seen, root)
            for key in ("pre_tasks", "tasks", "post_tasks", "handlers"):
                walk(play.get(key), pb, problems, roles_seen, root)
    for p in problems:
        print("FAIL check-mode: " + p)
    if problems:
        sys.exit(1)
    print("check-mode: %s: every check_mode: false task is read-only (%d roles)" % (", ".join(playbooks), len(roles_seen)))


if __name__ == "__main__":
    main()
