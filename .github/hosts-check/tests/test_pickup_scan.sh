#!/usr/bin/env bash
# The box's pickup scan (hosts/ansible/roles/agent_box/files/pickup-scan.py and .sh), with GitHub and the wake stubbed
# in-process and a throwaway App key, so no GitHub account is needed:
#   1. The token is asked for with the notebook alone and Contents and Pull requests read only, and revoked.
#   2. Parity: on 300 random sets of task notes, and on a hand-made one, the scan's ready list for each project is the
#      list `task_board.py next --all` prints (a copy of that script sits in pickup-oracle/), skip list included, and the
#      scan's stale claims are the ones `task_board.py stale --hours 3` prints for that project.
#   3. The first task of the ready list is announced; nothing is announced while a task marked for the project is
#      doing (cap 1); a claim older than 3 hours, or with no doing-since, is a finding; exactly 3 hours is not.
#   4. A task an open pull request changes is left out; a list cut off at 100 files or pull requests is a finding.
#   5. dry-run prints what it would post, posts nothing and leaves the memory alone, so the next run announces it.
#   6. run posts an announcement once; a label that stays posts nothing; a new first label posts; one that drops out
#      and comes back posts again; a failed post is tried again; findings go through checkpoint-note once.
#   7. A scan that cannot run (GitHub error, no settings, a note without text, no task folder) is a finding, and so is
#      a crash, named by its type only. In run mode a project with no standing pull request number is a finding too;
#      in dry-run it is not.
#   8. `show` prints the last report; a second run while one is going does nothing.
#   9. The wrapper passes dry-run, run and show only; the sessions' sudo line has dry-run and show only, pickup-note's
#      has log only, and the runner user's has none; the role installs the scripts, the settings file, the service
#      (SuccessExitStatus=3, mode from agent_box_pickup_mode, run for agent-notebook since 2026-11-19) and a timer every 10 minutes.
#  12. An announcement nobody claims is posted again 30 minutes after its last post (to the minute), at most 3 posts in
#      all; 30 minutes after the third the scan adds the finding `unclaimed: TASK-NNNN (<project>) announced 3 times with
#      no claim` and posts nothing more; a claim or a different first task resets the count; dry-run shows the repeat
#      and changes no memory; a state file from before this memory counts as one post, now. A stale claim's finding ends
#      `; reset it to ready by a PR`.
#  13. A stale `doing` claim (over 3 hours, or no valid doing-since) also posts `pickup-note post-stale <project> <label>`
#      once: its own memory key, never repeated while it stays, posted again after it drops out and returns; a claim
#      of exactly 3 hours does not; dry-run posts nothing and keeps no memory; a failed wake is tried again.
#  10. The oracle's copies still have the hashes the pickup-oracle README records.
#  11. Read-only and no model: the scan names no write call to GitHub except revoking its own token, and no model.
# Usage: .github/hosts-check/tests/test_pickup_scan.sh   (needs python3, openssl, PyYAML, Jinja2)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
role=$root/hosts/ansible/roles/agent_box
files=$role/files
oracle=$root/.github/hosts-check/tests/pickup-oracle
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

openssl genrsa -out "$t/github-app.pem" 2048 2>/dev/null

cat > "$t/harness.py" <<'PY'
import contextlib, datetime, importlib.util, io, json, os, random, shutil, subprocess, sys

src, tmp, oracle, case = sys.argv[1:5]
sys.dont_write_bytecode = True
T = datetime.datetime(2026, 11, 19, 12, 0, 0, tzinfo=datetime.timezone.utc)
TASKS = "01-notes/01t-tasks"


def fresh(name):
    spec = importlib.util.spec_from_file_location("scan", src)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.KEYS, m.WORK = tmp, os.path.join(tmp, "work_" + name)
    os.makedirs(m.WORK, exist_ok=True)
    m.now = lambda: T
    return m


def ago(**kw):
    return (T - datetime.timedelta(**kw)).strftime("%Y-%m-%dT%H:%MZ")


def note(label, state="ready", project="agent-notebook", pickup="agent-notebook", done_when='"a test passes"', extra=(), type_="task"):
    lines = ["---", "type: " + type_]
    if label:
        lines.append("label: " + label)
    lines += ["title: \"%s: x\"" % label, "project: " + project, "state: " + state]
    if pickup:
        lines.append("pickup: " + pickup)
    if done_when is not None:
        lines.append("done-when: " + done_when)
    lines += list(extra) + ["---", "# body", ""]
    return "\n".join(lines)


def settings(m, projects):
    json.dump({"projects": projects}, open(os.path.join(m.WORK, "pickup.json"), "w"))


def data(notes, prs=(), oid="abcdef1234567890", cut=(), extra=True, files_more=(), prs_more=False):
    entries = []
    for name, text in notes:
        entries.append({"name": name, "type": "blob", "object": {"text": None if name in cut else text, "isTruncated": False}})
    if extra:
        entries.append({"name": "01t-tasks.md", "type": "blob", "object": {"text": "---\ntype: hub\n---\n# Tasks\n", "isTruncated": False}})
        entries.append({"name": "sub", "type": "tree", "object": {}})
    nodes = [{"number": n, "files": {"pageInfo": {"hasNextPage": n in files_more}, "nodes": [{"path": p} for p in paths]}} for n, paths in prs]
    return {"repository": {"defaultBranchRef": {"target": {"oid": oid, "file": {"object": {"entries": entries}}}},
                           "pullRequests": {"pageInfo": {"hasNextPage": prs_more}, "nodes": nodes}}}


class FakeGH:
    answer = None
    fail = False
    calls = []

    def __init__(self):
        FakeGH.calls.append("open")

    def graphql(self, q, v):
        FakeGH.calls.append(("graphql", v))
        assert v == {"o": "jonhill90", "n": "agent-notebook", "p": TASKS}, v
        if FakeGH.fail:
            raise m.ScanError("GitHub's GraphQL API returned 502")
        a = FakeGH.answer
        return a() if callable(a) else a

    def close(self):
        FakeGH.calls.append("close")


def setup(name, projects=None):
    global m
    m = fresh(name)
    FakeGH.answer, FakeGH.fail, FakeGH.calls = None, False, []
    m.GitHub = FakeGH
    settings(m, projects if projects is not None else {"agent-notebook": {"repo": "agent-notebook", "number": 7}})
    posts = []
    m.post_ready = lambda p, l: posts.append(("ready", p, l)) or 0
    m.post_findings = lambda n: posts.append(("findings", n)) or 0
    m.post_stale = lambda p, l: posts.append(("stale", p, l)) or 0
    return posts


def run(mode):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = m.run(mode)
    return rc, out.getvalue()


results = []


def check(n, text, fn):
    try:
        fn()
        results.append("ok   %s. %s" % (n, text))
    except Exception as e:  # noqa: BLE001
        results.append("FAIL %s. %s [%s: %s]" % (n, text, type(e).__name__, e))


# ---- 1 token
def c1():
    mm = fresh("token")
    seen = []

    def http(method, url, bearer, body=None):
        seen.append((method, url, bearer, body))
        if url.endswith("/installation") and method == "GET":
            return 200, {"id": 42}
        if url.endswith("/access_tokens"):
            return 201, {"token": "ghs_SECRETTOKEN"}
        return 204, None
    mm.http = http
    json.dump({"github_app_id": 1}, open(os.path.join(mm.WORK, "ci-runner.json"), "w"))
    g = mm.GitHub()
    g.close()
    tok = [s for s in seen if s[1].endswith("/access_tokens")][0]
    assert seen[0][1] == "https://api.github.com/repos/jonhill90/agent-notebook/installation", seen[0]
    assert tok[3] == {"repositories": ["agent-notebook"], "permissions": {"contents": "read", "pull_requests": "read"}}, tok[3]
    assert seen[0][2].count(".") == 2 and seen[0][2] != "ghs_SECRETTOKEN"
    assert seen[-1][:3] == ("DELETE", "https://api.github.com/installation/token", "ghs_SECRETTOKEN"), seen[-1]
    assert [s[0] for s in seen if s[0] not in ("GET", "POST", "DELETE")] == []


# ---- 2 parity
sys.path.insert(0, oracle)
import task_board  # noqa: E402  (the copy of the notebook's script)


def oracle_next(root, project, skip):
    cmd = [sys.executable, "-I", os.path.join(oracle, "task_board.py"), "next", "--project", project, "--all"]
    if skip:
        cmd += ["--skip", ",".join(sorted(skip))]
    r = subprocess.run(cmd + [root], capture_output=True, text=True)
    assert r.returncode in (0, 3), (r.returncode, r.stderr)
    return [l.split("\t")[0] for l in r.stdout.splitlines()]


def oracle_stale(root, project):
    r = subprocess.run([sys.executable, "-I", os.path.join(oracle, "task_board.py"), "stale", "--now", T.strftime("%Y-%m-%dT%H:%MZ"),
                        "--hours", "3", root], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    rows = {l.split("\t")[0] for l in r.stdout.splitlines()}
    return sorted(l for l, fm in task_board.load(root) if l in rows and fm.get("pickup", "").strip() == project
                  and fm.get("state") == "doing")


def random_store(rng, n):
    labels = ["TASK-%04d" % (i + 1) for i in range(n)]
    notes = []
    for i in range(n):
        label = labels[i]
        extra = []
        r = rng.random()
        if r < 0.25:
            extra.append("waits-on: [%s]" % ", ".join(rng.sample(labels + ["TASK-9999"], rng.randint(1, 3))))
        elif r < 0.35:
            extra.append("waits-on: %s" % rng.choice(labels))
        elif r < 0.4:
            extra.append("waits-on: []")
        po = rng.random()
        if po < 0.4:
            extra.append("plan-order: %s" % rng.choice(["10", "20", "30", "5", "-3", "abc", "7"]))
        if rng.random() < 0.1:
            extra.append('jon-action: "tap the card"')
        if rng.random() < 0.05:
            extra.append("jon-action:")
        state = rng.choice(["ready", "ready", "ready", "doing", "done", "done", "blocked", "idea"])
        if state == "doing":
            extra.append("doing-since: %s" % rng.choice([ago(hours=1), ago(hours=3), ago(hours=3, minutes=1), ago(hours=9), "soon", "2026-13-40T99:99Z"]))
        pickup = rng.choice(["agent-notebook", "agent-notebook", "central-hub", "central-hub", "", "hill90-app"])
        dw = rng.choice(['"a test passes"'] * 6 + ["a test passes", '""', None, "   "])
        type_ = "task" if rng.random() > 0.05 else "idea"
        lab = label if rng.random() > 0.05 else ""
        text = note(lab, state=state, pickup=pickup, done_when=dw, extra=extra, type_=type_)
        if not lab:
            text = text.replace("title: \": x\"", "title: \"unlabelled\"")
        notes.append(("%016d.md" % (i + 1), text))
    notes.append(("9999999999999999.md", "no front matter here\n"))
    return notes


def c2():
    rng = random.Random(20261119)
    compared = ready_seen = stale_seen = 0
    for k in range(300):
        notes = random_store(rng, rng.randint(2, 30))
        root = os.path.join(tmp, "store%d" % k)
        os.makedirs(os.path.join(root, TASKS))
        for name, text in notes:
            open(os.path.join(root, TASKS, name), "w").write(text)
        setup("par%d" % k, {"agent-notebook": {"repo": "agent-notebook", "number": 7}, "central-hub": {"repo": "central-hub"}})
        # the labels an open pull request's files give (the board's --skip), by the oracle's own reading; a note with no
        # label is left out of the pull requests, because the board's --skip takes only TASK-NNNN labels
        by_file = {fm["file"]: label for label, fm in task_board.load(root)}
        files = [f.split("/")[-1] for f, l in by_file.items() if l.startswith("TASK-")]
        prs = [(100 + j, [TASKS + "/" + rng.choice(files)] + ["README.md"]) for j in range(rng.randint(0, 3))] if files else []
        FakeGH.answer = data(notes, prs)
        skip = {by_file[p] for _, paths in prs for p in paths if p in by_file}
        res = m.scan(T, "dry-run")
        for project in ("agent-notebook", "central-hub"):
            want = oracle_next(root, project, skip)
            got = res["lists"][project]
            assert got == want, "store %d %s: scan %s, task_board %s" % (k, project, got, want)
            compared += 1
            ready_seen += len(want)
            ws = oracle_stale(root, project)
            gs = sorted(f.split()[1] for f in res["findings"] if f.startswith("stale: ") and "(%s)" % project in f and "has been doing since" in f)
            assert gs == ws, "store %d %s: stale scan %s, task_board %s" % (k, project, gs, ws)
            stale_seen += len(ws)
            # what task_board.py stale skips (a doing-since it can't read) is a finding of its own in the scan
            nov = sorted({l for l, fm in task_board.load(root) if fm.get("state") == "doing" and fm.get("pickup", "").strip() == project
                          and task_board.minutes(fm.get("doing-since", "").strip()) is None})
            gn = sorted({f.split()[1] for f in res["findings"] if f.startswith("stale: ") and "no valid doing-since" in f and "(%s)" % project in f})
            assert gn == nov, "store %d %s: no-since scan %s, task_board %s" % (k, project, gn, nov)
    assert compared == 600 and ready_seen > 300 and stale_seen > 20, (compared, ready_seen, stale_seen)
    print("      parity: %d lists compared, %d ready entries, %d stale claims" % (compared, ready_seen, stale_seen), file=sys.stderr)


# ---- 3 announce, cap, stale
def board(*specs):
    return [("%016d.md" % (i + 1), s) for i, s in enumerate(specs)]


def c3():
    posts = setup("ann")
    FakeGH.answer = data(board(
        note("TASK-0010", extra=["plan-order: 20"]),
        note("TASK-0011", extra=["plan-order: 10"]),
        note("TASK-0012"),
        note("TASK-0013", extra=["waits-on: [TASK-0012]"]),             # waits on an open task
        note("TASK-0014", pickup="central-hub", project="central-hub"),  # another project's
    ))
    rc, out = run("run")
    assert rc == 3 and posts == [("ready", "agent-notebook", "TASK-0011")], (rc, posts)
    assert "list agent-notebook: TASK-0011 TASK-0010 TASK-0012\n" in out and "new: pickup: TASK-0011 is ready for agent-notebook\n" in out, out
    assert "board main abcdef1" in out and "TASK-0014" not in out, out
    # cap 1: a task in doing for the project stops the announcement; the list is still printed
    posts = setup("cap")
    FakeGH.answer = data(board(note("TASK-0010"), note("TASK-0011", state="doing", extra=["doing-since: " + ago(hours=1)])))
    rc, out = run("run")
    assert rc == 0 and posts == [] and "capped agent-notebook: TASK-0011 doing" in out and "list agent-notebook: TASK-0010" in out, (rc, posts, out)
    # a doing task with no pickup mark is not the project's claim
    posts = setup("cap2")
    FakeGH.answer = data(board(note("TASK-0010"), note("TASK-0011", state="doing", pickup=None)))
    rc, out = run("run")
    assert posts == [("ready", "agent-notebook", "TASK-0010")], posts
    # stale: more than 3 hours, none, and exactly 3 hours
    for since, finding in ((ago(hours=3, minutes=1), "stale: TASK-0011 (agent-notebook) has been doing since %s" % ago(hours=3, minutes=1)),
                           (None, "stale: TASK-0011 (agent-notebook) is doing with no valid doing-since"),
                           (ago(hours=3), None)):
        posts = setup("stale" + str(since)[-5:])
        FakeGH.answer = data(board(note("TASK-0010"), note("TASK-0011", state="doing", extra=["doing-since: " + since] if since else [])))
        rc, out = run("run")
        if finding:
            assert ("finding: " + finding + "; reset it to ready by a PR\n" in out or "new: " + finding + "; reset it to ready by a PR\n" in out), out
            assert ("finding: " + finding in out or "new: " + finding in out) and posts == [("stale", "agent-notebook", "TASK-0011"), ("findings", 1)] and rc == 3, (posts, out)
            assert "new: pickup: TASK-0011 is stale for agent-notebook\n" in out, out
        else:
            assert "stale" not in out and posts == [] and rc == 0, (posts, out)


def c3b():
    # two notes with one label (a fault the notebook's own checks refuse) must not crash the scan
    posts = setup("dup")
    FakeGH.answer = data(board(note("TASK-0010"), note("TASK-0010"), note("TASK-0011")))
    rc, out = run("run")
    assert "scan crashed" not in out and posts == [("ready", "agent-notebook", "TASK-0010")], (posts, out)
    assert "list agent-notebook: TASK-0010 TASK-0010 TASK-0011\n" in out, out


# ---- 4 pull request skip
def c4():
    posts = setup("skip")
    notes = board(note("TASK-0010"), note("TASK-0011"))
    FakeGH.answer = data(notes, prs=[(5, [TASKS + "/" + notes[0][0], "README.md"])])
    rc, out = run("run")
    assert posts == [("ready", "agent-notebook", "TASK-0011")] and "list agent-notebook: TASK-0011\n" in out, (posts, out)
    posts = setup("skipmore")
    FakeGH.answer = data(notes, prs=[(5, [])], files_more=(5,))
    rc, out = run("run")
    assert "scan error: open pull request #5 lists more than 100 files; the skip list may be incomplete" in out and ("findings", 1) in posts, (posts, out)
    posts = setup("prmore")
    FakeGH.answer = data(notes, prs=[], prs_more=True)
    rc, out = run("run")
    assert "scan error: more than 100 open pull requests" in out and ("findings", 1) in posts, (posts, out)


# ---- 5 dry-run
def c5():
    posts = setup("dry")
    FakeGH.answer = data(board(note("TASK-0010")))
    rc, out = run("dry-run")
    assert rc == 3 and posts == [] and "dry-run at 2026-11-19T12:00:00Z" in out, (rc, posts, out)
    assert "new: pickup: TASK-0010 is ready for agent-notebook\n" in out and "wake: dry-run: nothing posted; a run would post 1 announcement(s) and 0 finding(s)" in out, out
    rep = json.load(open(os.path.join(m.WORK, "state", "pickup-scan.json")))
    assert rep["known"] == [] and rep["mode"] == "dry-run" and rep["lists"] == {"agent-notebook": ["TASK-0010"]}, rep
    rc, out = run("dry-run")                    # a second dry-run says the same, so dry-run is not a memory
    assert rc == 3 and posts == [], (rc, posts)
    rc, out = run("run")                        # the first run after it still announces everything ready
    assert rc == 3 and posts == [("ready", "agent-notebook", "TASK-0010")], posts
    rc, out = run("dry-run")                    # and a dry-run after a run leaves what the run remembered
    rep = json.load(open(os.path.join(m.WORK, "state", "pickup-scan.json")))
    assert rc == 0 and rep["known"] == ["ready agent-notebook TASK-0010"] and posts == [("ready", "agent-notebook", "TASK-0010")], (rc, rep, posts)
    assert "ready: pickup: TASK-0010 is ready for agent-notebook" in out and "new:" not in out, out


# ---- 6 dedupe
def c6():
    posts = setup("dedupe")
    A, B = note("TASK-0010", extra=["plan-order: 1"]), note("TASK-0011", extra=["plan-order: 2"])
    FakeGH.answer = data(board(A, B))
    r = [run("run") for _ in range(2)]
    assert [x[0] for x in r] == [3, 0] and posts == [("ready", "agent-notebook", "TASK-0010")], (r, posts)
    assert r[1][1].strip().endswith("wake: nothing new"), r[1][1]
    # A is claimed: nothing is announced while it is doing; B is not announced either (cap 1)
    FakeGH.answer = data(board(note("TASK-0010", state="doing", extra=["plan-order: 1", "doing-since: " + ago(minutes=5)]), B))
    rc, out = run("run")
    assert rc == 0 and len(posts) == 1, (rc, posts)
    # A is done: B is the new first task and posts once
    FakeGH.answer = data(board(note("TASK-0010", state="done"), B))
    rc, out = run("run")
    assert rc == 3 and posts[-1] == ("ready", "agent-notebook", "TASK-0011") and len(posts) == 2, posts
    rc, out = run("run")
    assert rc == 0 and len(posts) == 2
    # A comes back as the first ready task: it posts again, because it had dropped out of the set
    FakeGH.answer = data(board(A, B))
    rc, out = run("run")
    assert posts[-1] == ("ready", "agent-notebook", "TASK-0010") and len(posts) == 3, posts
    # a failed post is tried again next run
    posts = setup("retry")
    FakeGH.answer = data(board(A))
    m.post_ready = lambda p, l: posts.append(("failed", p, l)) or 1
    rc, out = run("run")
    assert rc == 3 and "pickup-note failed for TASK-0010 (rc 1); the next run tries again" in out, out
    m.post_ready = lambda p, l: posts.append(("ready", p, l)) or 0
    rc, out = run("run")
    rc2, out2 = run("run")
    assert posts == [("failed", "agent-notebook", "TASK-0010"), ("ready", "agent-notebook", "TASK-0010")] and rc2 == 0, (posts, rc2)
    # findings: one post of the count of new ones, none for a repeat; a failed one is tried again
    posts = setup("finds")
    FakeGH.answer = data(board(A, note("TASK-0011", state="doing", extra=["doing-since: " + ago(hours=5)]),
                               note("TASK-0012", state="doing", extra=["doing-since: " + ago(hours=6)])))
    m.post_findings = lambda n: posts.append(("findings", n)) or 1
    rc, out = run("run")
    S = [("stale", "agent-notebook", "TASK-0011"), ("stale", "agent-notebook", "TASK-0012")]
    assert rc == 3 and posts == S + [("findings", 2)] and "checkpoint-note failed (rc 1)" in out, (rc, posts, out)
    m.post_findings = lambda n: posts.append(("findings", n)) or 0
    run("run")
    rc, out = run("run")
    assert posts == S + [("findings", 2), ("findings", 2)] and rc == 0, posts
    # a text with no age or run time in it: the same finding at 12:00 and 13:00 reads the same
    t1 = out
    m.now = lambda: T + datetime.timedelta(hours=1)
    FakeGH.answer = data(board(A, note("TASK-0011", state="doing", extra=["doing-since: " + ago(hours=5)]),
                               note("TASK-0012", state="doing", extra=["doing-since: " + ago(hours=6)])))
    rc, out = run("run")
    assert rc == 0 and posts == S + [("findings", 2), ("findings", 2)], (rc, posts)


# ---- 12 re-announce
def at(minutes):
    m.now = lambda: T + datetime.timedelta(minutes=minutes)


def report():
    return json.load(open(os.path.join(m.WORK, "state", "pickup-scan.json")))


def c12():
    A = note("TASK-0010")
    ann = ("ready", "agent-notebook", "TASK-0010")
    unclaimed = "unclaimed: TASK-0010 (agent-notebook) announced 3 times with no claim"
    posts = setup("again")
    FakeGH.answer = data(board(A))
    rc, out = run("run")                                  # 12:00 post 1
    assert rc == 3 and posts == [ann] and report()["posts"]["ready agent-notebook TASK-0010"] == {"first": "2026-11-19T12:00:00Z", "last": "2026-11-19T12:00:00Z", "count": 1}, (posts, report())
    at(29)
    rc, out = run("run")
    assert rc == 0 and posts == [ann] and "again:" not in out, (posts, out)
    # dry-run at 12:30 shows the repeat, posts nothing and leaves the memory alone
    at(30)
    before = report()["posts"]
    rc, out = run("dry-run")
    assert rc == 3 and posts == [ann] and "again: pickup: TASK-0010 is ready for agent-notebook (post 2 of 3)" in out and "a run would post 1 announcement(s)" in out, (rc, posts, out)
    assert report()["posts"] == before and report()["mode"] == "dry-run", report()
    rc, out = run("run")                                  # 12:30 post 2
    assert rc == 3 and posts == [ann, ann] and "posted TASK-0010 for agent-notebook again (post 2 of 3)" in out, (posts, out)
    assert report()["posts"]["ready agent-notebook TASK-0010"] == {"first": "2026-11-19T12:00:00Z", "last": "2026-11-19T12:30:00Z", "count": 2}, report()
    at(59)
    run("run")
    assert len(posts) == 2, posts
    at(60)
    rc, out = run("run")                                  # 13:00 post 3, no finding yet
    assert rc == 3 and posts == [ann] * 3 and "unclaimed" not in out, (posts, out)
    at(89)
    rc, out = run("run")
    assert rc == 0 and len(posts) == 3 and "unclaimed" not in out, (posts, out)
    at(90)
    rc, out = run("run")                                  # 13:30 the finding, not a fourth post
    assert rc == 3 and posts == [ann] * 3 + [("findings", 1)] and "new: " + unclaimed in out, (posts, out)
    for mins in (91, 120, 600):                           # then quiet: no fourth post, the finding does not post again
        at(mins)
        rc, out = run("run")
        assert rc == 0 and len(posts) == 4 and "finding: " + unclaimed in out and report()["posts"]["ready agent-notebook TASK-0010"]["count"] == 3, (mins, posts, out)
    # a claim resets it: nothing posts and the count is forgotten; when it is ready again it is a first post
    FakeGH.answer = data(board(note("TASK-0010", state="doing", extra=["doing-since: " + ago(minutes=-596)])))   # claimed 5 minutes before 601
    at(601)
    rc, out = run("run")
    assert rc == 0 and len(posts) == 4 and report()["posts"] == {} and "unclaimed" not in out, (posts, out, report())
    FakeGH.answer = data(board(A))
    at(602)
    rc, out = run("run")
    assert rc == 3 and posts[-1] == ann and len(posts) == 5 and report()["posts"]["ready agent-notebook TASK-0010"]["count"] == 1, (posts, report())
    # a different first task resets it too, and a failed repeat is tried again next run without counting
    posts = setup("again2")
    B = note("TASK-0011", extra=["plan-order: 5"])
    FakeGH.answer = data(board(A))
    run("run")
    at(30)
    m.post_ready = lambda p, l: posts.append(("failed", p, l)) or 1
    rc, out = run("run")
    assert rc == 3 and "pickup-note failed for TASK-0010 (rc 1); the next run tries again" in out and report()["posts"]["ready agent-notebook TASK-0010"]["count"] == 1, (out, report())
    m.post_ready = lambda p, l: posts.append(("ready", p, l)) or 0
    at(40)
    rc, out = run("run")
    assert rc == 3 and posts[-1] == ann and report()["posts"]["ready agent-notebook TASK-0010"]["count"] == 2, (posts, report())
    FakeGH.answer = data(board(A, B))
    at(41)
    run("run")
    assert posts[-1] == ("ready", "agent-notebook", "TASK-0011") and list(report()["posts"]) == ["ready agent-notebook TASK-0011"], (posts, report())
    # a state file written before this memory existed (a known key, no posts) counts as one post, now
    posts = setup("legacy")
    FakeGH.answer = data(board(A))
    os.makedirs(os.path.join(m.WORK, "state"))
    json.dump({"known": ["ready agent-notebook TASK-0010"]}, open(os.path.join(m.WORK, "state", "pickup-scan.json"), "w"))
    rc, out = run("run")
    assert rc == 0 and posts == [] and report()["posts"]["ready agent-notebook TASK-0010"]["count"] == 1, (posts, report())
    at(30)
    rc, out = run("run")
    assert rc == 3 and posts == [ann], posts


# ---- 13 stale wake
def c13():
    stale_f = lambda since: note("TASK-0011", state="doing", extra=["doing-since: " + since])
    wake = ("stale", "agent-notebook", "TASK-0011")
    posts = setup("sw")
    FakeGH.answer = data(board(note("TASK-0010"), stale_f(ago(hours=3, minutes=1))))
    rc, out = run("dry-run")                              # dry-run shows it, posts nothing, keeps no memory
    assert rc == 3 and posts == [] and "new: pickup: TASK-0011 is stale for agent-notebook\n" in out and "a run would post 1 announcement(s) and 1 finding(s)" in out, (rc, posts, out)
    assert report()["known"] == [], report()
    rc, out = run("run")                                  # run: the wake and the finding, each once
    assert rc == 3 and posts == [wake, ("findings", 1)] and "wake: posted stale TASK-0011 for agent-notebook; posted 1 finding(s)" in out, (posts, out)
    assert "stale agent-notebook TASK-0011" in report()["known"] and "ready agent-notebook TASK-0011" not in report()["known"], report()
    for mins in (10, 30, 600):                            # and never again while the claim stays stale (no repeat schedule)
        m.now = lambda mins=mins: T + datetime.timedelta(minutes=mins)
        FakeGH.answer = data(board(note("TASK-0010"), stale_f(ago(hours=3, minutes=1))))
        rc, out = run("run")
        assert rc == 0 and len(posts) == 2 and "stale: pickup: TASK-0011 is stale for agent-notebook" in out, (mins, posts, out)
    # it drops out (the claim is reset to ready, then done), then comes back stale: it posts again
    m.now = lambda: T + datetime.timedelta(minutes=700)
    FakeGH.answer = data(board(note("TASK-0010"), note("TASK-0011")))
    run("run")
    assert "stale agent-notebook TASK-0011" not in report()["known"], report()
    FakeGH.answer = data(board(note("TASK-0010"), stale_f(ago(hours=5))))
    n = len(posts)
    rc, out = run("run")
    assert [x for x in posts[n:] if x[0] == "stale"] == [wake], posts
    # no valid doing-since is stale too; a claim inside 3 hours, and exactly 3 hours, are not
    posts = setup("sw2")
    FakeGH.answer = data(board(note("TASK-0011", state="doing")))
    run("run")
    assert wake in posts, posts
    for since in (ago(hours=3), ago(minutes=5)):
        posts = setup("sw3" + since[-5:])
        FakeGH.answer = data(board(stale_f(since)))
        rc, out = run("run")
        assert posts == [] and "stale" not in out, (posts, out)
    # a failed wake is tried again next run, and the other post still goes
    posts = setup("sw4")
    FakeGH.answer = data(board(stale_f(ago(hours=4))))
    m.post_stale = lambda p, l: posts.append(("failed",) + (p, l)) or 1
    rc, out = run("run")
    assert rc == 3 and "pickup-note failed for stale TASK-0011 (rc 1); the next run tries again" in out and ("findings", 1) in posts, (posts, out)
    m.post_stale = lambda p, l: posts.append(("stale", p, l)) or 0
    run("run")
    rc, out = run("run")
    assert posts.count(wake) == 1 and rc == 0, posts
    # the ready key and the stale key are apart: a task that was announced ready then goes stale still posts the wake
    posts = setup("sw5")
    FakeGH.answer = data(board(note("TASK-0011")))
    run("run")
    FakeGH.answer = data(board(stale_f(ago(hours=4))))
    run("run")
    assert posts[0] == ("ready", "agent-notebook", "TASK-0011") and wake in posts, posts


# ---- 7 errors
def c7():
    base = board(note("TASK-0010"))
    posts = setup("e1")
    FakeGH.fail = True
    rc, out = run("run")
    assert rc == 3 and posts == [("findings", 1)] and "scan error: the board: GitHub's GraphQL API returned 502" in out, (rc, posts, out)
    assert FakeGH.calls[-1] == "close", FakeGH.calls
    posts = setup("e2")
    os.remove(os.path.join(m.WORK, "pickup.json"))
    rc, out = run("run")
    assert rc == 3 and posts == [("findings", 1)] and "pickup.json is missing or holds no projects" in out and "graphql" not in str(FakeGH.calls), (posts, out)
    posts = setup("e3")
    FakeGH.answer = data(base + board(note("TASK-0099"))[:0], cut=(base[0][0],))
    rc, out = run("run")
    assert "scan error: task note %s came back without its text" % base[0][0] in out and ("findings", 1) in posts, (posts, out)
    posts = setup("e4")
    FakeGH.answer = {"repository": {"defaultBranchRef": {"target": {"oid": "x", "file": None}}, "pullRequests": {"pageInfo": {}, "nodes": []}}}
    rc, out = run("run")
    assert "scan error: 01-notes/01t-tasks is not on agent-notebook's main" in out and posts == [("findings", 1)], (posts, out)
    posts = setup("e5")

    def boom():
        raise KeyError("secret-value")
    FakeGH.answer = boom
    r = [run("run") for _ in range(2)]
    assert [x[0] for x in r] == [3, 0] and posts == [("findings", 1)] and "new: scan crashed: KeyError" in r[0][1] and "secret-value" not in r[0][1], (posts, r)
    posts = setup("e6", {"Bad Name": {"repo": "x"}, "agent-notebook": {"repo": "agent-notebook", "number": 7}})
    FakeGH.answer = data(base)
    rc, out = run("run")
    assert "scan error: pickup.json names a project that is not a project name" in out and "Bad Name" not in out and ("ready", "agent-notebook", "TASK-0010") in posts, (posts, out)
    # no standing pull request number: a finding in run mode, not in dry-run, and the announcement is still tried
    posts = setup("e7", {"agent-notebook": {"repo": "agent-notebook"}})
    FakeGH.answer = data(base)
    rc, out = run("dry-run")
    assert "no standing pull request" not in out and posts == [], (posts, out)
    rc, out = run("run")
    assert "scan error: agent-notebook has no standing pull request in pickup.json, so nothing can be posted" in out and ("findings", 1) in posts, (posts, out)


# ---- 8 show and lock
def c8():
    posts = setup("show")
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        assert m.show() == 0
    assert out.getvalue() == "pickup-scan: no scan yet\n", out.getvalue()
    FakeGH.answer = data(board(note("TASK-0010"), note("TASK-0011", pickup="central-hub", project="central-hub")))
    run("run")
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        m.show()
    s = out.getvalue()
    assert s.startswith("pickup-scan: last scan (run) at 2026-11-19T12:00:00Z, board main abcdef1; wake: posted TASK-0010 for agent-notebook") and "list agent-notebook: TASK-0010" in s, s
    import fcntl
    held = open(os.path.join(m.WORK, "state", "pickup-scan.lock"), "w")
    fcntl.flock(held, fcntl.LOCK_EX)
    n = len(posts)
    rc, out = run("run")
    assert rc == 0 and out == "pickup-scan: another run is going\n" and len(posts) == n


# ---- 11 read-only
def c11():
    text = open(src).read()
    assert text.count('http("DELETE"') == 1 and "installation/token" in text
    writes = [l for l in text.splitlines() if 'http("POST"' in l or 'http("PUT"' in l or 'http("PATCH"' in l]
    # the only POSTs: the installation token, and the GraphQL read
    assert len(writes) == 2 and any("access_tokens" in l for l in writes) and any("/graphql" in l for l in writes), writes
    assert '"contents": "read", "pull_requests": "read"' in text
    lower = text.lower()
    assert "anthropic" not in lower and "claude" not in lower and "openai" not in lower


CASES = {"1": ("token for the notebook alone, Contents and Pull requests read only, signed JWT, revoked", c1),
         "2": ("parity with task_board.py next and stale on 300 random task sets (skip list included)", c2),
         "3": ("announces the first ready task; cap 1; a claim over 3 hours, or with no doing-since, is a finding", c3),
         "3b": ("two notes with one label sort and do not crash the scan", c3b),
         "4": ("a task an open pull request changes is left out; a cut-off list is a finding", c4),
         "5": ("dry-run prints what it would post, posts nothing and keeps no memory", c5),
         "6": ("posts a new label once; a returning label posts again; failed posts retry; findings post as a count", c6),
         "12": ("an unclaimed announcement is posted again after 30 minutes, 3 posts at most, then an unclaimed finding; a claim resets it; dry-run keeps no memory", c12),
         "13": ("a stale claim also posts the stale wake once per key (its own key), dry-run keeps no memory, a failed wake retries", c13),
         "7": ("a scan that can't run, a crash and a project with no pull request number are findings", c7),
         "8": ("show prints the last report; a second run at once does nothing", c8),
         "11": ("read-only and no model: one DELETE (its own token), two POSTs (token, GraphQL), no model named", c11)}
for n, (text, fn) in CASES.items():
    check(n, text, fn)
print("\n".join(results))
sys.exit(1 if any(r.startswith("FAIL") for r in results) else 0)
PY

python3 -I "$t/harness.py" "$files/pickup-scan.py" "$t" "$oracle" all > "$t/h.out" 2> "$t/h.err"
rc=$?
cat "$t/h.out"
grep -E '^ +parity:' "$t/h.err" | sed 's/^ */      /'
if [[ $rc != 0 ]]; then fail=1; sed -n '1,20p' "$t/h.err"; fi

# 9
w1=$(bash "$files/pickup-scan.sh" sweep 2>&1; echo "rc=$?")
w2=$(bash "$files/pickup-scan.sh" run extra 2>&1; echo "rc=$?")
w3=$(bash "$files/pickup-scan.sh" 2>&1; echo "rc=$?")
nsudo=$(python3 - "$role" <<'PY'
import sys, yaml, jinja2
role = sys.argv[1] + "/"
d = yaml.safe_load(open(role + "defaults/main.yml"))
ws = {w["name"]: w for w in d["agent_box_wrappers"]}
env = jinja2.Environment(loader=jinja2.FileSystemLoader(role + "templates"))
env.filters["regex_replace"] = lambda s, a, b: __import__("re").sub(a, b, s)
env.filters["bool"] = bool
txt = env.get_template("sudoers.j2").render(agent_box_wrappers=[ws["pickup-scan"], ws["pickup-note"]], agent_box_user="sess",
        agent_box_keys_user="keys", agent_box_libexec_dir="/x", agent_box_self_apply=False, agent_box_runner_user="run")
sess = [l for l in txt.splitlines() if l.startswith("sess ALL=")]
run = [l for l in txt.splitlines() if l.startswith("run ALL=")]
print(ws["pickup-scan"]["args"] == ["dry-run", "run", "show"], ws["pickup-note"]["args"] == ["post *", "log"], sess == [
    "sess ALL=(keys) NOPASSWD: /x/pickup-scan.sh dry-run, /x/pickup-scan.sh show",
    "sess ALL=(keys) NOPASSWD: /x/pickup-note.sh log"], run == [],
    d["agent_box_pickup_mode"] == "run", d["agent_box_pickup_scan"] is True, d["agent_box_pickup_projects"] == {"agent-notebook": {"repo": "agent-notebook", "number": 753}},
    d["agent_box_pickup_scan_on_calendar"] == "*-*-* *:00/10:00 UTC")
PY
)
tasks=$(cat "$role/tasks/main.yml")
svc=$(cat "$role/templates/pickup-scan.service.j2")
tmr=$(cat "$role/templates/pickup-scan.timer.j2")
specs=$(cat "$role/meta/argument_specs.yml")
cal=$(systemd-analyze calendar --iterations=3 "*-*-* *:00/10:00 UTC" 2>/dev/null | grep -c 'Next elapse\|Iter\.' || true)
if [[ $w1 == *"usage: pickup-scan dry-run | run | show"*"rc=2" && $w2 == *"rc=2" && $w3 == *"rc=2" &&
      $nsudo == "True True True True True True True True" &&
      $tasks == *'dest: "{{ agent_box_libexec_dir }}/pickup-scan.py"'* && $tasks == *"name: pickup-scan.timer"* &&
      $tasks == *'dest: "{{ agent_box_work_dir }}/pickup.json"'* &&
      $svc == *"ExecStart={{ agent_box_libexec_dir }}/pickup-scan.sh {{ agent_box_pickup_mode }}"* && $svc == *"SuccessExitStatus=3"* &&
      $svc == *"User={{ agent_box_keys_user }}"* && $tmr == *"OnCalendar={{ agent_box_pickup_scan_on_calendar }}"* &&
      $specs == *"choices: [dry-run, run]"* ]]; then
  ok "9. the wrapper passes dry-run, run and show only; sessions get dry-run, show and pickup-note log, the runner nothing; the role installs the scripts, settings, service (exit 3 ok, run for agent-notebook on #753) and a 10-minute timer"
else bad "9. [$w1] [$w2] [$w3] [$nsudo]"; fi
if command -v systemd-analyze >/dev/null 2>&1; then
  if systemd-analyze calendar "*-*-* *:00/10:00 UTC" >/dev/null 2>&1 && [[ ${cal:-0} -ge 1 ]]; then
    ok "9b. the timer's calendar parses with systemd-analyze"
  else bad "9b. systemd-analyze did not accept the timer's calendar"; fi
fi

# 10
if (cd "$oracle" && grep -q "$(sha256sum task_board.py | cut -d' ' -f1)" README.md && grep -q "$(sha256sum task_owners.py | cut -d' ' -f1)" README.md); then
  ok "10. the oracle's copies still have the hashes its README records"
else bad "10. pickup-oracle/ differs from the hashes in its README"; fi

exit $fail
