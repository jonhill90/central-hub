#!/usr/bin/env python3
"""Every open task has a live owner.

Usage: task_owners.py check [<store>]

Reads every task note in 01-notes/01t-tasks/ (front matter `type: task`) and the owner register
04-resources/04a-assets/04as-scripts/owners.tsv. A task whose `state` is not `done` fails when:
  - `owner` is empty,
  - `owner` is not a row of the register (exact text),
  - the owner's `states` column does not allow the task's state (for example `coordinator` may not hold a
    `ready` task, and `backlog` may not hold a `doing` one),
  - the owner is `backlog` and the task has no `backlog-reason:`.
The register itself fails on a repeated owner, an unknown kind or state word, or a thread row without a
cmsg_ id. Deterministic: no network, no agent, no clock; the same files give the same faults.
Why: Jon, 2026-11-09 07:58 UTC, "what else did you orphan"; the orphan sweep (Library plans/orphan-sweep.md)
found open tasks owned by resolved threads, by "coordinator", or by nobody.
"""
import csv, os, re, sys

TASKS = os.path.join("01-notes", "01t-tasks")
REGISTER = os.path.join("04-resources", "04a-assets", "04as-scripts", "owners.tsv")
STATES = ["jon", "doing", "ready", "blocked", "idea", "parked", "done"]
KINDS = {"person", "coordinator", "thread", "backlog"}
THREAD_ID = re.compile(r"^cmsg_[0-9A-Za-z]+$")


def front_matter(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---", 4)
    out = {}
    for line in text[4:end].splitlines():
        m = re.match(r"^([A-Za-z][\w-]*):\s*(.*)$", line)
        if m:
            v = m.group(2).strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            out[m.group(1)] = v
    return out


def load_register(root):
    owners, faults = {}, []
    path = os.path.join(root, REGISTER)
    with open(path, encoding="utf-8") as f:
        rows = [l for l in f if l.strip() and not l.startswith("#")]
    for i, row in enumerate(csv.DictReader(rows, delimiter="\t")):
        name, kind = (row.get("owner") or "").strip(), (row.get("kind") or "").strip()
        where = f"{REGISTER} row {i + 1} ({name or 'no name'})"
        states = [s.strip() for s in (row.get("states") or "").split(",") if s.strip()]
        allowed = set(STATES) - {"done"} if states == ["all"] else set(states)
        if not name:
            faults.append(f"{where}: empty owner")
            continue
        if name in owners:
            faults.append(f"{where}: owner listed twice")
        if kind not in KINDS:
            faults.append(f"{where}: kind '{kind}' is not one of {sorted(KINDS)}")
        if states != ["all"] and (not states or any(s not in STATES or s == "done" for s in states)):
            faults.append(f"{where}: states '{row.get('states')}' must be 'all' or open state words")
        if kind == "thread" and not THREAD_ID.match((row.get("thread") or "").strip()):
            faults.append(f"{where}: a thread row needs its cmsg_ id")
        owners[name] = {"kind": kind, "states": allowed}
    return owners, faults


def check(root):
    owners, faults = load_register(root)
    counts = {}
    folder = os.path.join(root, TASKS)
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".md"):
            continue
        fm = front_matter(os.path.join(folder, name))
        if fm.get("type") != "task":
            continue
        label, state, owner = fm.get("label", name), fm.get("state", ""), fm.get("owner", "").strip()
        where = f"{TASKS}/{name} ({label})"
        if state not in STATES:
            faults.append(f"{where}: state '{state}' is not one of {STATES}")
            continue
        if state == "done":
            continue
        if not owner:
            faults.append(f"{where}: open task ({state}) has no owner")
            continue
        o = owners.get(owner)
        if o is None:
            faults.append(f"{where}: owner '{owner}' is not in {REGISTER}; name a live owner or 'backlog' with backlog-reason")
            continue
        if state not in o["states"]:
            faults.append(f"{where}: owner '{owner}' may not hold a '{state}' task (allowed: {', '.join(sorted(o['states']))})")
        if o["kind"] == "backlog" and not fm.get("backlog-reason", "").strip():
            faults.append(f"{where}: owner is backlog but backlog-reason is empty")
        counts[owner] = counts.get(owner, 0) + 1
    return faults, counts


def main(argv):
    if len(argv) < 2 or argv[1] != "check":
        print(__doc__)
        return 2
    root = argv[2] if len(argv) > 2 else "."
    faults, counts = check(root)
    for f in faults:
        print("task_owners:", f)
    summary = ", ".join(f"{k} {v}" for k, v in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])))
    print(f"task_owners: {len(faults)} faults; open tasks by owner: {summary}")
    return 1 if faults else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
