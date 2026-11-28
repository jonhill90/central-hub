#!/usr/bin/env python3
"""The box pickup scan: it reads the notebook's task board and wakes a session only when a project has a new ready task.

  pickup-scan.py dry-run   scan once, print what it would post, post nothing, and remember nothing about what was posted
  pickup-scan.py run       scan once, print the findings, post the ones that are new
  pickup-scan.py show      print the last scan's report

Run as user `keys` through pickup-scan.sh (sudo, dry-run and show only) or the 10-minute timer (run or dry-run, as
agent_box_pickup_mode says; dry-run is the default). Installed root-owned by the agent_box role. No model runs here.

Once per run, over GitHub (an App token narrowed to the notebook, with Contents and Pull requests read), it reads
the task notes on the notebook's main and the files that its open pull requests change, in one GraphQL call, so no
checkout is needed and nothing is written. For each project named in /var/lib/agent-box/pickup.json it then:

  1. builds the project's ready list with this file's own copy of the board's selector (`ready` below; the same rules
     as `task_board.py next --all`, which test_pickup_scan.sh checks against a copy of that script): `state: ready`,
     `pickup: <project>`, a `done-when`, no `jon-action`, every `waits-on` task `done`, not changed by an open pull
     request; `plan-order` first, then the label. This copy is why the scan never runs code from the notebook's
     main under the App key.
  2. stops there if a task with `pickup: <project>` is `doing` (work in progress is capped at 1). If that claim is
     more than STALE_AGE old by its `doing-since`, or has none, that is a finding instead, and its text names the
     exit: `; reset it to ready by a PR`. The scan writes nothing to the notebook (its token is read-only). The stale
     claim also wakes a session: `pickup-note post-stale <project> <TASK-NNNN>`, the fixed comment
     `pickup: TASK-NNNN is stale for <project>.` on the standing pull request, once per claim (see below).
  3. otherwise announces the first task of the list, the one a worker would take, with
     `pickup-note post <project> <TASK-NNNN>`: one fixed comment on that project's standing pull request.
  4. posts that announcement again if nobody claims it: while the same task is still the first of the list and
     nothing is `doing`, the scan posts it again once REANNOUNCE_AGE (30 minutes) has passed since its last post, at
     most REANNOUNCE_POSTS (3) posts in all for that announcement. REANNOUNCE_AGE after the third post it adds the
     finding `unclaimed: TASK-NNNN (<project>) announced 3 times with no claim`. The posts' times and count are kept
     in the state file's `posts` (a post's time is the scan's own clock, to the minute). An announcement that drops
     out (claimed, done, or no longer first) loses its count, so if it returns it starts again at one post.

A finding is a line of text with no age or run time in it, so the same finding reads the same every run. Only an
announcement, a stale wake (key `stale <project> <label>`, its own key, apart from the ready key) or a finding that
was not in the last `run`'s set posts: an announcement through pickup-note, findings
through `checkpoint-note post <count>` (the checkpoint's own pull request). One that stays posts nothing; one that
drops out and comes back posts again; a failed post is tried again next run. A scan that cannot run, and a crash
of the scan, are findings too, so a broken scan never reads as a quiet board. `dry-run` never changes that memory,
so the first `run` after it still announces everything ready, and no repeat post is counted.
Exit: 0 nothing new, 3 something new (the timer's unit counts 3 as success), 2 usage.
No token, key or note text is printed: only project names, task labels, note names and times.
"""
import base64
import datetime
import fcntl
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

OWNER = "jonhill90"
NOTEBOOK = "agent-notebook"
TASKS = "01-notes/01t-tasks"
STALE_AGE = datetime.timedelta(hours=3)             # a `doing` claim older than this is a finding (the work-in-progress cap's age)
REANNOUNCE_AGE = datetime.timedelta(minutes=30)     # an announcement nobody claimed is posted again after this long
REANNOUNCE_POSTS = 3                                # at most this many posts in all for one announcement, then a finding
RESET_HINT = "; reset it to ready by a PR"          # the exit from a stale claim, said in the finding
PROJECT = re.compile(r"^[a-z][a-z0-9-]{0,40}$")
LABEL = r"TASK-\d{4,}"
SINCE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})Z$")
MAX_POST = 999                                      # checkpoint-note's largest count

KEYS = "/etc/agent-keys"
WORK = "/var/lib/agent-box"
LIBEXEC = "/usr/local/libexec/agent-box"
API = "https://api.github.com"


def now():
    return datetime.datetime.now(datetime.timezone.utc)


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


class ScanError(Exception):
    pass


# --- GitHub (the same small client as checkpoint-scan.py, kept as its own reviewed copy) ------------------------

def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def http(method, url, bearer, body=None):
    """One call. The token stays in this process (a header), never in a command line. Returns (status, parsed body)."""
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + bearer, "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "central-hub-pickup-scan"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, None
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise ScanError("GitHub did not answer %s %s (%s)" % (method, url.split("?")[0], type(e).__name__))


class GitHub:
    """An installation token for the notebook with Contents and Pull requests read only, revoked by close()."""

    def __init__(self):
        settings = os.path.join(WORK, "ci-runner.json")
        try:
            app_id = str(json.load(open(settings))["github_app_id"])
        except (OSError, ValueError, KeyError):
            raise ScanError("%s is missing or holds no github_app_id" % settings)
        t = int(now().timestamp())
        head = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
        claims = b64url(json.dumps({"iat": t - 60, "exp": t + 540, "iss": app_id}).encode())
        signed = subprocess.run(["openssl", "dgst", "-sha256", "-sign", os.path.join(KEYS, "github-app.pem")],
                                input=(head + "." + claims).encode(), capture_output=True)
        if signed.returncode != 0:
            raise ScanError("the App key did not sign the JWT")
        jwt = head + "." + claims + "." + b64url(signed.stdout)
        code, inst = http("GET", "%s/repos/%s/%s/installation" % (API, OWNER, NOTEBOOK), jwt)
        if code != 200 or not isinstance(inst, dict):
            raise ScanError("no App installation on %s/%s (GitHub returned %s)" % (OWNER, NOTEBOOK, code))
        code, tok = http("POST", "%s/app/installations/%s/access_tokens" % (API, inst["id"]), jwt,
                         {"repositories": [NOTEBOOK], "permissions": {"contents": "read", "pull_requests": "read"}})
        if code != 201 or not isinstance(tok, dict) or not tok.get("token"):
            raise ScanError("no read token for %s (GitHub returned %s)" % (NOTEBOOK, code))
        self.token = tok["token"]

    def graphql(self, query, variables):
        code, body = http("POST", API + "/graphql", self.token, {"query": query, "variables": variables})
        if code != 200 or not isinstance(body, dict) or body.get("errors"):
            raise ScanError("GitHub's GraphQL API returned %s%s" % (code, " with errors" if isinstance(body, dict) and body.get("errors") else ""))
        return body["data"]

    def close(self):
        try:
            http("DELETE", API + "/installation/token", self.token)
        except ScanError:
            pass


# --- The board's selector: this file's own copy of task_board.py's `ready` and `stale` -------------------------------

def labels(raw):
    return re.findall(LABEL, raw or "")


def front_matter(text):
    """The key: value lines between the first two `---` lines, quotes stripped, as the board's own reader does."""
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


def load(notes):
    """[(label, fm)] for every task note, in file-name order; fm has 'file'. notes: [(file name, text)]."""
    out = []
    for name, text in sorted(notes):
        fm = front_matter(text)
        if fm.get("type") != "task":
            continue
        fm["file"] = "%s/%s" % (TASKS, name)
        out.append((fm.get("label", name), fm))
    return out


def ready(tasks, project, skip=()):
    """[(label, fm)] ready for one project, best first (plan-order, none last, then label)."""
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
        # the file name last, so two notes with one label (the notebook's checks refuse that) sort instead of crashing
        out.append(((int(po) if po.lstrip("-").isdigit() else 10 ** 9, label, fm["file"]), label, fm))
    return [(label, fm) for _, label, fm in sorted(out, key=lambda row: row[0])]


def minutes(since):
    m = SINCE.match(since or "")
    if not m:
        return None
    y, mo, d, h, mi = map(int, m.groups())
    try:
        t = datetime.datetime(y, mo, d, h, mi)
    except ValueError:
        return None
    return int((t - datetime.datetime(1970, 1, 1)).total_seconds() // 60)


def doing(tasks, project):
    """[(label, fm)] of the project's marked tasks that are in `doing`."""
    return [(label, fm) for label, fm in tasks
            if fm.get("state") == "doing" and fm.get("pickup", "").strip() == project]


# --- The scan --------------------------------------------------------------------------------------------------

BOARD = """query($o: String!, $n: String!, $p: String!) {
  repository(owner: $o, name: $n) {
    defaultBranchRef { target { ... on Commit {
      oid
      file(path: $p) { object { ... on Tree { entries { name type object { ... on Blob { text isTruncated } } } } } }
    } } }
    pullRequests(states: OPEN, first: 100) {
      pageInfo { hasNextPage }
      nodes { number files(first: 100) { pageInfo { hasNextPage } nodes { path } } }
    }
  }
}"""


def settings():
    """{project: {repo, number?}} from pickup.json, and the faults that make a project unusable."""
    path = os.path.join(WORK, "pickup.json")
    try:
        projects = json.load(open(path))["projects"]
        if not isinstance(projects, dict):
            raise ValueError
    except (OSError, ValueError, KeyError):
        raise ScanError("%s is missing or holds no projects" % path)
    faults, good = [], {}
    for name, cfg in sorted(projects.items()):
        if not PROJECT.match(name) or not isinstance(cfg, dict):
            faults.append("scan error: pickup.json names a project that is not a project name")
        else:
            good[name] = cfg
    return good, faults


def scan(t, mode):
    """{main, lists, capped, announce, findings}: the board read once, each project judged."""
    res = {"main": "", "lists": {}, "capped": {}, "announce": [], "stale": [], "findings": []}
    try:
        projects, faults = settings()
    except ScanError as e:
        res["findings"].append("scan error: %s" % e)
        return res
    res["findings"] += faults
    if not projects:
        return res
    try:
        gh = GitHub()
    except ScanError as e:
        res["findings"].append("scan error: %s" % e)
        return res
    try:
        try:
            data = gh.graphql(BOARD, {"o": OWNER, "n": NOTEBOOK, "p": TASKS})
        except ScanError as e:
            res["findings"].append("scan error: the board: %s" % e)
            return res
    finally:
        gh.close()
    repo = data.get("repository") or {}
    target = (repo.get("defaultBranchRef") or {}).get("target") or {}
    entries = (((target.get("file") or {}).get("object") or {}).get("entries"))
    if entries is None:
        res["findings"].append("scan error: %s is not on %s's main" % (TASKS, NOTEBOOK))
        return res
    res["main"] = str(target.get("oid", ""))
    notes = []
    for e in entries:
        name = e.get("name", "")
        if e.get("type") != "blob" or not name.endswith(".md"):
            continue
        blob = e.get("object") or {}
        if blob.get("text") is None or blob.get("isTruncated"):
            res["findings"].append("scan error: task note %s came back without its text" % name)
            continue
        notes.append((name, blob["text"]))
    tasks = load(notes)
    # Tasks an open pull request already changes are not taken again (the board's --skip).
    prs = repo.get("pullRequests") or {}
    changed = set()
    if (prs.get("pageInfo") or {}).get("hasNextPage"):
        res["findings"].append("scan error: more than 100 open pull requests; the skip list may be incomplete")
    for pr in prs.get("nodes") or []:
        files = pr.get("files") or {}
        if (files.get("pageInfo") or {}).get("hasNextPage"):
            res["findings"].append("scan error: open pull request #%s lists more than 100 files; the skip list may be incomplete" % pr.get("number"))
        changed |= {f.get("path") for f in files.get("nodes") or []}
    skip = {label for label, fm in tasks if fm["file"] in changed}
    n = minutes(iso(t)[:16] + "Z")
    for project, cfg in projects.items():
        rows = ready(tasks, project, skip)
        res["lists"][project] = [label for label, _ in rows]
        claims = doing(tasks, project)
        if claims:
            res["capped"][project] = [label for label, _ in claims]
            for label, fm in claims:
                since = fm.get("doing-since", "").strip()
                m = minutes(since)
                if m is None:
                    res["findings"].append("stale: %s (%s) is doing with no valid doing-since%s" % (label, project, RESET_HINT))
                    res["stale"].append((project, label))
                elif n - m > STALE_AGE.total_seconds() // 60:
                    res["findings"].append("stale: %s (%s) has been doing since %s%s" % (label, project, since, RESET_HINT))
                    res["stale"].append((project, label))
            continue
        if mode == "run" and not isinstance(cfg.get("number"), int):
            res["findings"].append("scan error: %s has no standing pull request in pickup.json, so nothing can be posted" % project)
        if rows:
            res["announce"].append((project, rows[0][0]))
    res["findings"] = sorted(set(res["findings"]))
    res["stale"] = sorted(set(res["stale"]))
    return res


# --- Report, memory and the wake -------------------------------------------------------------------------------

def key(project, label):
    return "ready %s %s" % (project, label)


def parse(s):
    try:
        return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    except (TypeError, ValueError):
        return None


def minutes_since(last, t):
    """Whole minutes from the time `last` (an iso string) to t, both cut to the minute so a run's seconds don't matter."""
    a = parse(last)
    if a is None:
        return None
    cut = lambda x: x.replace(second=0, microsecond=0)
    return int((cut(t) - cut(a)).total_seconds() // 60)


def stale_key(project, label):
    return "stale %s %s" % (project, label)


def post_stale(project, label):
    """The stale wake: one fixed comment on the standing pull request. Returns pickup-note's exit code."""
    return subprocess.run([os.path.join(LIBEXEC, "pickup-note.sh"), "post-stale", project, label]).returncode


def post_ready(project, label):
    """The wake: one fixed comment on the project's standing pull request. Returns pickup-note's exit code."""
    return subprocess.run([os.path.join(LIBEXEC, "pickup-note.sh"), "post", project, label]).returncode


def post_findings(count):
    """Findings go to the checkpoint's own pull request through checkpoint-note, as checkpoint-scan's do."""
    return subprocess.run([os.path.join(LIBEXEC, "checkpoint-note.sh"), "post", str(min(count, MAX_POST))]).returncode


def hub(args):
    """The hub dispatcher's wake (hub-fire.py, its own rows and mode; off unless hub-fire.json turns it on). Its outcome
    is printed and never changes the scan's own posts or exit code; a missing or failing hub-fire is a printed line only."""
    path = os.path.join(LIBEXEC, "hub-fire.py")
    if not os.path.exists(path):
        return
    try:
        out = subprocess.run([path] + args, capture_output=True, text=True, timeout=120)
        for line in (out.stdout + out.stderr).splitlines():
            print(line)
    except (OSError, subprocess.SubprocessError) as e:
        print("pickup-scan: hub-fire did not run (%s)" % type(e).__name__)


def run(mode):
    state_dir = os.path.join(WORK, "state")
    os.makedirs(state_dir, exist_ok=True)
    lock = open(os.path.join(state_dir, "pickup-scan.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("pickup-scan: another run is going")
        return 0
    t = now()
    try:
        res = scan(t, mode)
    except Exception as e:  # any other fault is a finding too, named by its type only (its text may hold data)
        res = {"main": "", "lists": {}, "capped": {}, "announce": [], "stale": [], "findings": ["scan crashed: %s" % type(e).__name__]}
    statef = os.path.join(state_dir, "pickup-scan.json")
    try:
        last = json.load(open(statef))
    except (OSError, ValueError):
        last = {}
    known = set(last.get("known", []))
    old = last.get("posts") if isinstance(last.get("posts"), dict) else {}
    announce = [(p, l, key(p, l)) for p, l in res["announce"]]
    # What each announcement still announced has had posted: {key: {first, last, count}}. A known key with no entry
    # (written before this memory existed) counts as posted once, now.
    posts_now = {}
    for p, l, k in announce:
        e = old.get(k)
        if k in known and not (isinstance(e, dict) and parse(e.get("last")) and isinstance(e.get("count"), int)):
            e = {"first": iso(t), "last": iso(t), "count": 1}
        if k in known:
            posts_now[k] = e
    again, label_of = [], {k: (p, l) for p, l, k in announce}
    for k, e in posts_now.items():
        if minutes_since(e["last"], t) < REANNOUNCE_AGE.total_seconds() // 60:
            continue
        p, l = label_of[k]
        if e["count"] < REANNOUNCE_POSTS:
            again.append((p, l))
        else:
            res["findings"].append("unclaimed: %s (%s) announced %d times with no claim" % (l, p, REANNOUNCE_POSTS))
    res["findings"] = sorted(set(res["findings"]))
    new_ready = [(p, l) for p, l, k in announce if k not in known]
    stale = [(p, l, stale_key(p, l)) for p, l in res["stale"]]
    new_stale = [(p, l) for p, l, k in stale if k not in known]
    new_other = [f for f in res["findings"] if f not in known]
    print("pickup-scan: %s at %s, board main %s" % (mode, iso(t), res["main"][:7] or "not read"))
    for project in sorted(res["lists"]):
        print("list %s: %s" % (project, " ".join(res["lists"][project]) or "none"))
        if project in res["capped"]:
            print("capped %s: %s doing" % (project, " ".join(res["capped"][project])))
    posted = set()
    for p, l, k in announce:
        text = "pickup: %s is ready for %s" % (l, p)
        if (p, l) in again:
            print("again: %s (post %d of %d)" % (text, posts_now[k]["count"] + 1, REANNOUNCE_POSTS))
        else:
            print(("new: " if (p, l) in new_ready else "ready: ") + text)
    for p, l, k in stale:
        print(("new: " if (p, l) in new_stale else "stale: ") + "pickup: %s is stale for %s" % (l, p))
    for f in res["findings"]:
        print(("new: " if f in new_other else "finding: ") + f)
    if mode == "dry-run":
        wake = "dry-run: nothing posted"
        if new_ready or again or new_stale or new_other:
            wake += "; a run would post %d announcement(s) and %d finding(s)" % (len(new_ready) + len(again) + len(new_stale), len(new_other))
    else:
        wake = "nothing new"
        bits = []
        for p, l in new_ready + again:
            k = key(p, l)
            rc = post_ready(p, l)
            if rc == 0:
                posted.add(k)
                if (p, l) in again:
                    e = posts_now[k]
                    posts_now[k] = {"first": e["first"], "last": iso(t), "count": e["count"] + 1}
                    bits.append("posted %s for %s again (post %d of %d)" % (l, p, e["count"] + 1, REANNOUNCE_POSTS))
                else:
                    posts_now[k] = {"first": iso(t), "last": iso(t), "count": 1}
                    bits.append("posted %s for %s" % (l, p))
            else:
                bits.append("pickup-note failed for %s (rc %d); the next run tries again" % (l, rc))
        for p, l in new_stale:
            rc = post_stale(p, l)
            if rc == 0:
                posted.add(stale_key(p, l))
                bits.append("posted stale %s for %s" % (l, p))
            else:
                bits.append("pickup-note failed for stale %s (rc %d); the next run tries again" % (l, rc))
        if new_other:
            rc = post_findings(len(new_other))
            if rc == 0:
                posted.update(new_other)
                bits.append("posted %d finding(s)" % len(new_other))
            else:
                bits.append("checkpoint-note failed (rc %d); the next run tries again" % rc)
        if bits:
            wake = "; ".join(bits)
    print("pickup-scan: wake: " + wake)
    for project in sorted(res["capped"]):          # a claim is on main: the project's ring is answered
        if mode == "run":
            hub(["ack", project])
    for p, l, _ in announce:                       # the first ready task: hub-fire decides whether to fire
        hub(["ring", p, l] + (["--dry-run"] if mode == "dry-run" else []))
    if mode == "run":
        known_next = sorted(k for k in [k for _, _, k in announce] + [k for _, _, k in stale] + res["findings"] if k in known or k in posted)
        posts_next = {k: posts_now[k] for k in known_next if k in posts_now}
    else:
        known_next = sorted(known)
        posts_next = old
    report = {"time": iso(t), "mode": mode, "main": res["main"], "lists": res["lists"], "capped": res["capped"],
              "findings": res["findings"], "known": known_next, "posts": posts_next, "wake": wake}
    tmp = statef + ".part"
    with open(tmp, "w") as f:
        json.dump(report, f, indent=1, sort_keys=True)
        f.write("\n")
    os.replace(tmp, statef)
    subprocess.run(["logger", "-t", "pickup-scan", "%s: %d ready, %d finding(s); wake: %s"
                    % (mode, len(announce), len(res["findings"]), wake)], capture_output=True)
    return 3 if (new_ready or again or new_stale or new_other) else 0


def show():
    statef = os.path.join(WORK, "state", "pickup-scan.json")
    try:
        r = json.load(open(statef))
    except (OSError, ValueError):
        print("pickup-scan: no scan yet")
        return 0
    print("pickup-scan: last scan (%s) at %s, board main %s; wake: %s"
          % (r.get("mode"), r.get("time"), str(r.get("main", ""))[:7] or "not read", r.get("wake")))
    for project, labs in sorted((r.get("lists") or {}).items()):
        print("list %s: %s" % (project, " ".join(labs) or "none"))
    for project, labs in sorted((r.get("capped") or {}).items()):
        print("capped %s: %s doing" % (project, " ".join(labs)))
    for f in r.get("findings", []):
        print("finding: " + f)
    return 0


def main(argv):
    if argv in (["run"], ["dry-run"]):
        return run(argv[0])
    if argv == ["show"]:
        return show()
    print("usage: pickup-scan dry-run | run | show", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
