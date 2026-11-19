#!/usr/bin/env python3
"""The board's pickup fields, and the ready list a project's pickup run takes its next task from.

Usage:
  task_board.py check [<store>]
  task_board.py next --project <p> [--skip TASK-a,TASK-b] [--all] [<store>]
  task_board.py stale --now <YYYY-MM-DDTHH:MMZ> [--hours N] [<store>]
  task_board.py label [--ref origin/main] [<store>]

`check` reads every task note in 01-notes/01t-tasks/ (front matter `type: task`) and fails when:
  - `done-when` is present but empty or more than one line;
  - `pickup` names no project map `02-projects/<p>.md`, differs from the task's `project`, or sits on a task
    with no `done-when` or with a `jon-action` (a pickable task can't need Jon);
  - a `waits-on` or `parent` label names no task, or names the task itself;
  - the `waits-on` edges or the `parent` chain make a loop;
  - a `done` task is the parent of a task that is not `done`;
  - `doing-since` is not `YYYY-MM-DDTHH:MMZ`, sits on a task that is not `doing`, or is missing on a
    `doing` task that has `pickup`.
`next` prints the ready list for one project, best first: tasks with `state: ready`, `pickup: <p>`, a
`done-when`, no `jon-action`, every `waits-on` task `done`, and not named by `--skip` (the pickup run passes the
tasks an open pull request already changes). Order: `plan-order` (lowest first, none last), then label.
Without `--all` it prints only the first. Exit 0 with a line, 3 when the list is empty.
`label` prints the next free task label: one more than the highest `label: TASK-NNNN` in the task notes of
`--ref` (default `origin/main`; run `git fetch` first) and of the working tree, so two branches never both take
the local highest plus one. It can still clash with an unmerged branch; `task_keys.py` on the merged tree catches that.
`stale` lists `doing` tasks whose `doing-since` is more than `--hours` (default 6) before `--now`: claims a
pickup run may take back.

Deterministic: no network, no agent, no clock (`stale` takes the time as an argument); the same files give
the same output.
Why: Jon, 2026-11-18 07:21 UTC (same task number, per project, front matter with deterministic processes) and
08:03 UTC ("You pick and iterate ... do the reaserch and use the reaserch"). RB-0261 catalogue rows M43
(done condition written first: Library research/agent-task-management-methods T2, T29, T38, C13), M27 and M28
(computed ready list and its order: T1 `bd ready`, T29 Taskmaster `next`, T30 Claude Code teams do not
self-claim a blocked task), M29 (no loops: T19), M49 and M56 (parent and child: T24, T1, C9), M18 (claims
expire: C5, T15, T14); measured gap H2 (40 of 47 ready tasks had no done test).
Exit path: drop the CI step and the pickup run; the keys are plain front matter.
"""
import os, re, sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import task_owners  # noqa: E402  (front_matter, TASKS)

LABEL = re.compile(r"^TASK-\d{4,}$")
SINCE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})Z$")
PROJECTS = "02-projects"


def labels(raw):
    return re.findall(r"TASK-\d{4,}", raw or "")


def load(root):
    """[(label, fm)] for every task note, fm with 'file' and the raw done-when line."""
    folder = os.path.join(root, task_owners.TASKS)
    out = []
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".md"):
            continue
        path = os.path.join(folder, name)
        fm = task_owners.front_matter(path)
        if fm.get("type") != "task":
            continue
        fm["file"] = f"{task_owners.TASKS}/{name}"
        out.append((fm.get("label", name), fm))
    return out


def loops(edges):
    """Each loop in a {node: [next, ...]} graph, once, as a list of nodes."""
    state, found = {}, []

    def visit(node, trail):
        state[node] = 1
        for nxt in edges.get(node, []):
            if state.get(nxt) == 1:
                found.append(trail[trail.index(nxt):] + [nxt] if nxt in trail else [node, nxt])
            elif not state.get(nxt):
                visit(nxt, trail + [nxt])
        state[node] = 2

    for n in sorted(edges):
        if not state.get(n):
            visit(n, [n])
    return found


def minutes(since):
    m = SINCE.match(since or "")
    if not m:
        return None
    import datetime
    y, mo, d, h, mi = map(int, m.groups())
    try:
        t = datetime.datetime(y, mo, d, h, mi)
    except ValueError:
        return None
    return int((t - datetime.datetime(1970, 1, 1)).total_seconds() // 60)


try:
    import yaml
except ImportError:  # the check still runs, with the quote test only
    yaml = None

QUOTED = re.compile(r'^([A-Za-z][\w-]*):\s*"(.*)"\s*$')


def front_matter_faults(path, where):
    """Faults in one task's front matter: with PyYAML, whatever yaml.safe_load rejects (file and line);
    without it, any double-quoted value with an unescaped inner double quote."""
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if not text.startswith("---\n") or text.find("\n---", 4) < 0:
        return []
    block = text[4:text.find("\n---", 4)]
    if yaml is not None:
        try:
            yaml.safe_load(block)
        except yaml.YAMLError as e:
            mark = getattr(e, "problem_mark", None)
            line = f", line {mark.line + 2}" if mark else ""  # +1 for 1-based, +1 for the opening ---
            problem = getattr(e, "problem", None) or str(e)
            return [f"{where}: front matter is not valid YAML{line}: {problem}"]
        return []
    out = []
    for n, line in enumerate(block.splitlines(), 2):
        m = QUOTED.match(line)
        if m and re.search(r'(?<!\\)"', m.group(2)):
            out.append(f"{where}: line {n}: {m.group(1)} has an unescaped double quote inside a double-quoted "
                       "value, which is not valid YAML (PyYAML is not installed, so only this test ran)")
    return out


def check(root):
    tasks = load(root)
    by = {}
    for label, fm in tasks:
        by.setdefault(label, fm)  # duplicates are task_keys.py's fault
    faults = []
    waits, parents = {}, {}
    for label, fm in tasks:
        where = f"{fm['file']} ({label})"
        dw = fm.get("done-when")
        if dw is not None and not dw.strip():
            faults.append(f"{where}: done-when is empty")
        faults.extend(front_matter_faults(os.path.join(root, fm["file"]), where))
        pickup = fm.get("pickup", "").strip()
        if pickup:
            if not os.path.isfile(os.path.join(root, PROJECTS, pickup + ".md")):
                faults.append(f"{where}: pickup '{pickup}' names no project map {PROJECTS}/{pickup}.md")
            if pickup != fm.get("project", "").strip():
                faults.append(f"{where}: pickup '{pickup}' is not the task's project '{fm.get('project', '')}'")
            if not (dw or "").strip():
                faults.append(f"{where}: pickup is set but done-when is not; write the done test first")
            if fm.get("jon-action", "").strip():
                faults.append(f"{where}: pickup is set on a task with a jon-action; a pickable task can't need Jon")
        w = labels(fm.get("waits-on"))
        for x in w:
            if x == label:
                faults.append(f"{where}: waits on itself")
            elif x not in by:
                faults.append(f"{where}: waits-on {x}: no task has that label")
        waits[label] = [x for x in w if x in by and x != label]
        raw_parent = fm.get("parent", "").strip()
        if raw_parent:
            if not LABEL.match(raw_parent):
                faults.append(f"{where}: parent '{raw_parent}' is not one task label like TASK-0123")
            elif raw_parent == label:
                faults.append(f"{where}: is its own parent")
            elif raw_parent not in by:
                faults.append(f"{where}: parent {raw_parent}: no task has that label")
            else:
                parents[label] = [raw_parent]
                if by[raw_parent].get("state") == "done" and fm.get("state") != "done":
                    faults.append(f"{by[raw_parent]['file']} ({raw_parent}): done, but its child {label} is "
                                  f"'{fm.get('state')}'")
        since = fm.get("doing-since", "").strip()
        if since:
            if minutes(since) is None:
                faults.append(f"{where}: doing-since '{since}' is not YYYY-MM-DDTHH:MMZ")
            if fm.get("state") != "doing":
                faults.append(f"{where}: doing-since is set but state is '{fm.get('state')}'")
        elif fm.get("state") == "doing" and pickup:
            faults.append(f"{where}: a picked-up task in doing needs doing-since (the claim time)")
    for kind, edges in (("waits-on", waits), ("parent", parents)):
        for loop in loops(edges):
            faults.append(f"{kind} loop: {' -> '.join(loop)}")
    return faults


def ready(root, project, skip=()):
    tasks = load(root)
    by = dict(tasks)
    out = []
    for label, fm in tasks:
        if fm.get("state") != "ready" or fm.get("pickup", "").strip() != project:
            continue
        if not fm.get("done-when", "").strip() or fm.get("jon-action", "").strip() or label in skip:
            continue
        if any(by.get(x, {}).get("state") != "done" for x in labels(fm.get("waits-on"))):
            continue
        po = fm.get("plan-order", "").strip()
        key = (int(po) if po.lstrip("-").isdigit() else 10 ** 9, label)
        out.append((key, label, fm))
    return [(label, fm) for _, label, fm in sorted(out)]


def stale(root, now, hours):
    n = minutes(now)
    if n is None:
        raise SystemExit(f"task_board: --now '{now}' is not YYYY-MM-DDTHH:MMZ")
    out = []
    for label, fm in load(root):
        m = minutes(fm.get("doing-since", "").strip())
        if fm.get("state") == "doing" and m is not None and n - m > hours * 60:
            out.append((label, fm, (n - m) // 60))
    return out


def next_label(root, ref="origin/main"):
    import subprocess
    nums = [int(x[5:]) for _, fm in load(root) for x in labels(fm.get("label"))]
    try:
        out = subprocess.run(["git", "-C", root, "grep", "-h", "-E", r"^label: TASK-[0-9]+", ref, "--",
                              task_owners.TASKS], capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        raise SystemExit(f"task_board: cannot read {ref}: {getattr(e, 'stderr', e)}")
    nums += [int(x[5:]) for x in labels(out)]
    return f"TASK-{max(nums, default=0) + 1:04d}"


def opt(argv, name, default=None):
    if name in argv:
        i = argv.index(name)
        if i + 1 < len(argv):
            return argv[i + 1]
    return default


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    valued = {"--project", "--skip", "--now", "--hours", "--ref"}
    rest, i = [], 2
    while i < len(argv):
        if argv[i] in valued:
            i += 2
            continue
        if not argv[i].startswith("--"):
            rest.append(argv[i])
        i += 1
    root = rest[0] if rest else "."
    if cmd == "check":
        faults = check(root)
        for f in faults:
            print("task_board:", f)
        print(f"task_board: {len(faults)} faults")
        return 1 if faults else 0
    if cmd == "next":
        project = opt(argv, "--project")
        if not project:
            print(__doc__)
            return 2
        skip = set(labels(opt(argv, "--skip", "")))
        rows = ready(root, project, skip)
        for label, fm in rows if "--all" in argv else rows[:1]:
            print(f"{label}\t{fm['file']}\t{fm.get('title', '')}\tdone-when: {fm.get('done-when', '')}")
        if not rows:
            print(f"task_board: no ready task for {project}", file=sys.stderr)
            return 3
        return 0
    if cmd == "stale":
        now = opt(argv, "--now")
        if not now:
            print(__doc__)
            return 2
        hours = int(opt(argv, "--hours", "6"))
        for label, fm, h in stale(root, now, hours):
            print(f"{label}\t{fm['file']}\tdoing for {h} h (since {fm.get('doing-since')})\towner {fm.get('owner', '')}")
        return 0
    if cmd == "label":
        print(next_label(root, opt(argv, "--ref", "origin/main")))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
