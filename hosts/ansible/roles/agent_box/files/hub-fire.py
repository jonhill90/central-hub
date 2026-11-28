#!/usr/bin/env python3
"""The hub dispatcher's wake: it starts a project's worker task through that task's API trigger, at most once per ring.

  hub-fire.py ring <project> <TASK-NNNN> [--dry-run]   the pickup scan says this task is first ready: fire, or not
  hub-fire.py ack <project>                            the pickup scan saw a claim for the project: the ring is answered
  hub-fire.py show                                     print the rings and their attempts

Run by pickup-scan.py as the keys user (installed root-owned by the agent_box role). No model runs here.

A ring is per project, not per task: it is answered when any claim for the project is on the notebook's main, because the
worker rereads main and may rightly take a different first task. The rung label is only a hint for the worker.

The rows in hub-wakes.sqlite are the record, and are kept across restarts and crashes:
  1. ring with no open ring for the project opens one and makes attempt 1.
  2. Before each call the attempt is written as `reserved` and committed. After the call it becomes `sent` (the API
     answered with a session), `timeout` (no answer; counts as sent and waits for the claim) or `refused` (an HTTP error
     code). A `reserved` row left by a crash counts as sent. Every attempt row uses one of the ATTEMPTS tries.
  3. A ring on an open ring fires again only once GAPS[n-1] minutes have passed since attempt n, so two rings close
     together give one call. After the last attempt and its gap the ring is marked shown and reported as unanswered,
     once; nothing more is fired for it until an ack.
  4. ack answers the open ring. If the same task is still first ready after that, the next ring is a new ring.
  5. dry-run decides and prints, and writes and calls nothing. Mode off (the default in hub-fire.json) does nothing.

Settings: <work>/hub-fire.json {"mode": "off|dry-run|on", "projects": {"<project>": {"trigger": "trig_..."}}}.
Token: <keys>/hub-fire/<project>.token, the trigger's bearer token, one line. The owner's card makes it; until then mode
"on" reports `no token` and makes no attempt. The token is sent only as a header to api.anthropic.com and never printed.
The fire carries no text unless the project sets "text": true, and then only the label, checked against TASK-NNNN.
Exit: 0 nothing done, 3 fired (or would fire, in dry-run), 4 unanswered reported, 2 usage or bad settings.
"""
import datetime
import fcntl
import json
import os
import re
import sqlite3
import sys
import urllib.error
import urllib.request

KEYS = "/etc/agent-keys"
WORK = "/var/lib/agent-box"
API = "https://api.anthropic.com/v1/claude_code/routines/%s/fire"
BETA = "experimental-cc-routine-2026-04-01"
VERSION = "2023-06-01"
ATTEMPTS = 3
GAPS = [30, 60, 120]                     # minutes to wait after attempt n before attempt n+1 (or, after the last, before unanswered)
PROJECT = re.compile(r"^[a-z][a-z0-9-]{0,40}$")
LABEL = re.compile(r"^TASK-\d{4,}$")
TRIGGER = re.compile(r"^trig_[A-Za-z0-9]{10,60}$")
SESSION = re.compile(r"^[A-Za-z0-9_-]{1,100}$")


def now():
    return datetime.datetime.now(datetime.timezone.utc)


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse(s):
    return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)


class Bad(Exception):
    pass


def settings():
    path = os.path.join(WORK, "hub-fire.json")
    try:
        s = json.load(open(path))
    except OSError:
        return {"mode": "off", "projects": {}}
    except ValueError:
        raise Bad("%s is not JSON" % path)
    mode, projects = s.get("mode", "off"), s.get("projects", {})
    if mode not in ("off", "dry-run", "on") or not isinstance(projects, dict):
        raise Bad("%s: mode must be off, dry-run or on, and projects a map" % path)
    for p, cfg in projects.items():
        if not PROJECT.match(p) or not isinstance(cfg, dict) or not TRIGGER.match(str(cfg.get("trigger", ""))):
            raise Bad("%s: a project needs a project name and a trigger id trig_..." % path)
    return {"mode": mode, "projects": projects}


def db():
    d = os.path.join(WORK, "state")
    os.makedirs(d, exist_ok=True)
    c = sqlite3.connect(os.path.join(d, "hub-wakes.sqlite"), isolation_level=None, timeout=30)
    c.execute("CREATE TABLE IF NOT EXISTS rings (ring INTEGER PRIMARY KEY, project TEXT NOT NULL, label TEXT NOT NULL,"
              " opened TEXT NOT NULL, answered TEXT, shown TEXT)")
    c.execute("CREATE TABLE IF NOT EXISTS attempts (ring INTEGER NOT NULL, n INTEGER NOT NULL, state TEXT NOT NULL,"
              " at TEXT NOT NULL, code INTEGER, session TEXT, PRIMARY KEY (ring, n))")
    return c


def lock():
    d = os.path.join(WORK, "state")
    os.makedirs(d, exist_ok=True)
    f = open(os.path.join(d, "hub-fire.lock"), "w")
    fcntl.flock(f, fcntl.LOCK_EX)            # one ring or ack at a time; waits rather than skips, so no ring is lost
    return f


def open_ring(c, project):
    return c.execute("SELECT ring, label, opened, shown FROM rings WHERE project = ? AND answered IS NULL"
                     " ORDER BY ring DESC LIMIT 1", (project,)).fetchone()


def attempts(c, ring):
    return c.execute("SELECT n, state, at FROM attempts WHERE ring = ? ORDER BY n", (ring,)).fetchall()


def decide(c, project, t):
    """('fire', ring or None, n) | ('wait', ring, n) | ('unanswered', ring, n) | ('quiet', ring, n): what a ring does now."""
    r = open_ring(c, project)
    if r is None:
        return "fire", None, 1
    ring, _, _, shown = r
    rows = attempts(c, ring)
    n = len(rows)
    if n == 0:
        return "fire", ring, 1
    since = int((t - parse(rows[-1][2])).total_seconds() // 60)
    if since < GAPS[n - 1]:
        return "wait", ring, n
    if n < ATTEMPTS:
        return "fire", ring, n + 1
    return ("quiet" if shown else "unanswered"), ring, n


def call(trigger, token, body):
    """(state, code, session): one POST. The token is a header in this process only."""
    req = urllib.request.Request(API % trigger, data=json.dumps(body).encode(), method="POST", headers={
        "Authorization": "Bearer " + token, "anthropic-beta": BETA, "anthropic-version": VERSION,
        "Content-Type": "application/json", "User-Agent": "central-hub-hub-fire"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = json.loads(resp.read() or b"{}")
            sid = str(raw.get("claude_code_session_id") or raw.get("session_id") or "")
            return "sent", resp.status, sid if SESSION.match(sid) else ""
    except urllib.error.HTTPError as e:
        return "refused", e.code, ""
    except (urllib.error.URLError, OSError, ValueError):
        return "timeout", None, ""


def token(project):
    try:
        v = open(os.path.join(KEYS, "hub-fire", project + ".token")).read().strip()
    except OSError:
        return None
    return v or None


def ring(project, label, dry):
    s = settings()
    if not PROJECT.match(project) or not LABEL.match(label):
        raise Bad("ring needs a project name and a TASK-NNNN label")
    if s["mode"] == "off":
        print("hub-fire: off")
        return 0
    cfg = s["projects"].get(project)
    if cfg is None:
        print("hub-fire: %s has no trigger in hub-fire.json; nothing fired" % project)
        return 0
    dry = dry or s["mode"] == "dry-run"
    t = now()
    lk = lock()
    try:
        c = db()
        what, rid, n = decide(c, project, t)
        if what == "wait":
            print("hub-fire: %s rung, attempt %d of %d is waiting for its claim; nothing fired" % (project, n, ATTEMPTS))
            return 0
        if what == "quiet":
            print("hub-fire: %s unanswered after %d attempts, already reported; nothing fired" % (project, n))
            return 0
        if what == "unanswered":
            if not dry:
                c.execute("UPDATE rings SET shown = ? WHERE ring = ?", (iso(t), rid))
            print("hub-fire: unanswered: %s rung %d times with no claim" % (project, n))
            return 4
        if dry:
            print("hub-fire: dry-run: would fire %s for %s (attempt %d of %d)" % (project, label, n, ATTEMPTS))
            return 3
        tok = token(project)
        if tok is None:
            print("hub-fire: no token for %s; nothing fired" % project)
            return 0
        c.execute("BEGIN IMMEDIATE")
        if rid is None:
            rid = c.execute("INSERT INTO rings (project, label, opened) VALUES (?, ?, ?)", (project, label, iso(t))).lastrowid
        c.execute("INSERT INTO attempts (ring, n, state, at) VALUES (?, ?, 'reserved', ?)", (rid, n, iso(t)))
        c.execute("COMMIT")
        state, code, sid = call(cfg["trigger"], tok, {"text": label} if cfg.get("text") is True else {})
        c.execute("UPDATE attempts SET state = ?, code = ?, session = ? WHERE ring = ? AND n = ?", (state, code, sid, rid, n))
        print("hub-fire: fired %s for %s (attempt %d of %d): %s%s%s" % (project, label, n, ATTEMPTS, state,
              "" if code is None else " %d" % code, " session " + sid if sid else ""))
        return 3
    finally:
        lk.close()


def ack(project):
    if not PROJECT.match(project):
        raise Bad("ack needs a project name")
    if settings()["mode"] != "on":
        return 0
    t = now()
    lk = lock()
    try:
        c = db()
        r = open_ring(c, project)
        if r is None:
            return 0
        c.execute("UPDATE rings SET answered = ? WHERE ring = ?", (iso(t), r[0]))
        print("hub-fire: %s ring for %s answered by a claim" % (project, r[1]))
        return 0
    finally:
        lk.close()


def show():
    path = os.path.join(WORK, "state", "hub-wakes.sqlite")
    if not os.path.exists(path):
        print("hub-fire: no rings yet")
        return 0
    c = db()
    for ring_, project, label, opened, answered, shown in c.execute("SELECT * FROM rings ORDER BY ring"):
        end = "answered " + answered if answered else ("unanswered, shown " + shown if shown else "open")
        print("ring %d %s %s opened %s, %s" % (ring_, project, label, opened, end))
        for n, state, at in attempts(c, ring_):
            print("  attempt %d %s at %s" % (n, state, at))
    return 0


def main(argv):
    try:
        if len(argv) in (3, 4) and argv[0] == "ring" and (len(argv) == 3 or argv[3] == "--dry-run"):
            return ring(argv[1], argv[2], len(argv) == 4)
        if len(argv) == 2 and argv[0] == "ack":
            return ack(argv[1])
        if argv == ["show"]:
            return show()
    except Bad as e:
        print("hub-fire: %s" % e, file=sys.stderr)
        return 2
    print("usage: hub-fire ring <project> <TASK-NNNN> [--dry-run] | ack <project> | show", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
