#!/usr/bin/env python3
"""The hourly checkpoint as a box script: it reads, finds, and wakes a session only on a finding.

  checkpoint-scan.py run    scan once, print the findings, post through checkpoint-note when they are new
  checkpoint-scan.py show   print the last scan's report

Run as user `keys` through checkpoint-scan.sh (sudo) or the hourly timer. Installed root-owned by the agent_box role.
Four checks, each over GitHub (an App token narrowed to the two repositories with Contents and Pull requests read)
and the box's own pass ledger (/var/lib/agent-box/passes, which pass-record writes and the merge sweep reads):

  1. said-i-would: a row of the notebook's said-i-would.md whose State is Open and whose line on main last changed
     more than OPEN_AGE ago (git blame through GitHub's GraphQL API, so no checkout is needed).
  2. unpassed merge: a pull request on either main merged within MERGE_WINDOW whose head has no reviewer pass.
  3. ledger time: a ledger line recorded within MERGE_WINDOW whose relay time is later than the time the box wrote it,
     or more than a day before it. The post's own time is not readable from the box, so a relay time a few seconds off
     the post (F218) is not caught here.
  4. moved head: an open pull request whose head has no reviewer pass, while an earlier head of it has one.

A check that cannot run is itself a finding, so a broken scan never reads as a clean one. The findings, sorted, are
the report. A report that differs from the last one posted is posted as `checkpoint-note post <count>`; the same
report is not posted twice in a row, and an empty report clears that memory. Exit: 0 no finding, 3 findings, 2 usage.
No token, key or ledger value but heads, numbers and times is printed.
"""
import base64
import datetime
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

OWNER = "jonhill90"
REPOS = ("central-hub", "agent-notebook")          # "both mains"
NOTEBOOK = "agent-notebook"
SAID_PATH = "00-inbox/00d-dashboards/said-i-would.md"
OPEN_AGE = datetime.timedelta(hours=2)
MERGE_WINDOW = datetime.timedelta(hours=2)
LEDGER_SLACK = datetime.timedelta(seconds=60)       # clock skew allowed between a relay time and the box's own time
LEDGER_OLDEST = datetime.timedelta(days=1)
PASS_ROLES = ("reviewer",)                          # the role the sweep needs (pr-merge-verdict.py ROLES)
MAX_POST = 999                                      # checkpoint-note's largest count

KEYS = "/etc/agent-keys"
WORK = "/var/lib/agent-box"
LIBEXEC = "/usr/local/libexec/agent-box"
API = "https://api.github.com"


def now():
    return datetime.datetime.now(datetime.timezone.utc)


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_time(s):
    return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)


class ScanError(Exception):
    pass


# --- GitHub ----------------------------------------------------------------------------------------------------

def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def http(method, url, bearer, body=None):
    """One call. The token stays in this process (a header), never in a command line. Returns (status, parsed body)."""
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + bearer, "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "central-hub-checkpoint-scan"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, None
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise ScanError("GitHub did not answer %s %s (%s)" % (method, url.split("?")[0], type(e).__name__))


class GitHub:
    """An installation token for REPOS with Contents and Pull requests read only, revoked by close()."""

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
                         {"repositories": list(REPOS), "permissions": {"contents": "read", "pull_requests": "read"}})
        if code != 201 or not isinstance(tok, dict) or not tok.get("token"):
            raise ScanError("no read token for %s (GitHub returned %s)" % (", ".join(REPOS), code))
        self.token = tok["token"]

    def get(self, path):
        code, body = http("GET", API + path, self.token)
        if code != 200:
            raise ScanError("GitHub returned %s for %s" % (code, path.split("?")[0]))
        return body

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


# --- The ledger ------------------------------------------------------------------------------------------------

def ledger(repo):
    """Every ledger line of one repository, as dicts. A line that does not parse is skipped (the sweep refuses it)."""
    d = os.path.join(WORK, "passes", repo)
    lines = []
    if not os.path.isdir(d):
        return lines
    for f in sorted(os.listdir(d)):
        if not f.endswith(".jsonl"):
            continue
        try:
            text = open(os.path.join(d, f)).read()
        except OSError:
            continue
        for raw in text.splitlines():
            try:
                o = json.loads(raw)
            except ValueError:
                continue
            if isinstance(o, dict):
                lines.append(o)
    return lines


def passed_heads(lines, repo):
    """{head: set of PR numbers} for heads that hold a reviewer pass in this repository."""
    out = {}
    for o in lines:
        if o.get("role") in PASS_ROLES and o.get("repo") == "%s/%s" % (OWNER, repo) and isinstance(o.get("head"), str):
            out.setdefault(o["head"], set()).add(o.get("pr"))
    return out


# --- The four checks -------------------------------------------------------------------------------------------

BLAME = """query($o: String!, $n: String!, $p: String!) {
  repository(owner: $o, name: $n) { defaultBranchRef { target { ... on Commit {
    oid
    file(path: $p) { object { ... on Blob { text } } }
    blame(path: $p) { ranges { startingLine endingLine commit { committedDate } } }
  } } } }
}"""


def said_rows(text):
    """(line number, said, state) for each row of the first table whose header has a State column."""
    rows, state_col, in_table = [], None, False
    for n, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if not s.startswith("|"):
            if in_table:
                break
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if state_col is None:
            if "State" in cells:
                state_col, in_table = cells.index("State"), True
            continue
        if all(re.fullmatch(r":?-{3,}:?", c) for c in cells):
            continue
        if len(cells) > state_col:
            rows.append((n, cells[0], cells[state_col]))
    return rows


def check_said(gh, t):
    data = gh.graphql(BLAME, {"o": OWNER, "n": NOTEBOOK, "p": SAID_PATH})
    target = (((data.get("repository") or {}).get("defaultBranchRef") or {}).get("target") or {})
    text = ((target.get("file") or {}).get("object") or {}).get("text")
    ranges = (target.get("blame") or {}).get("ranges")
    if text is None or ranges is None:
        raise ScanError("%s is not on %s's main" % (SAID_PATH, NOTEBOOK))
    changed = {}
    for r in ranges:
        when = parse_time(r["commit"]["committedDate"])
        for n in range(r["startingLine"], r["endingLine"] + 1):
            changed[n] = when
    out = []
    for n, said, state in said_rows(text):
        if not state.lower().startswith("open") or n not in changed:
            continue
        age = t - changed[n]
        if age > OPEN_AGE:
            out.append("said-i-would: line %d (said %s) is Open, unchanged since %s (%dh %02dm)"
                       % (n, said, iso(changed[n]), age.seconds // 3600 + age.days * 24, age.seconds % 3600 // 60))
    return out


def check_merges(gh, t, repo, heads):
    out = []
    for p in gh.get("/repos/%s/%s/pulls?state=closed&sort=updated&direction=desc&per_page=100" % (OWNER, repo)) or []:
        if not p.get("merged_at"):
            continue
        merged = parse_time(p["merged_at"])
        if t - merged > MERGE_WINDOW:
            continue
        head = (p.get("head") or {}).get("sha", "")
        if head not in heads:
            out.append("unpassed merge: %s#%s merged %s at head %s with no reviewer pass in the ledger"
                       % (repo, p["number"], iso(merged), head[:7]))
    return out


def check_ledger_times(t, repo, lines):
    out = []
    for o in lines:
        try:
            box, relay = parse_time(o["box_time"]), parse_time(o["relay_time"])
        except (KeyError, TypeError, ValueError):
            continue
        if t - box > MERGE_WINDOW:
            continue
        if relay > box + LEDGER_SLACK:
            why = "is later than the box recorded it (%s)" % iso(box)
        elif box - relay > LEDGER_OLDEST:
            why = "is more than a day before the box recorded it (%s)" % iso(box)
        else:
            continue
        out.append("ledger time: %s#%s head %s, relay %s at %s %s"
                   % (repo, o.get("pr"), str(o.get("head", ""))[:7], o.get("relay_ref", "?"), iso(relay), why))
    return out


def check_moved_heads(gh, repo, heads):
    out = []
    by_pr = {}
    for h, prs in heads.items():
        for n in prs:
            by_pr.setdefault(n, []).append(h)
    for p in gh.get("/repos/%s/%s/pulls?state=open&per_page=100" % (OWNER, repo)) or []:
        n, head = p.get("number"), (p.get("head") or {}).get("sha", "")
        if head in heads or n not in by_pr:
            continue
        old = sorted(h[:7] for h in by_pr[n])
        out.append("moved head: %s#%s head %s has no reviewer pass; the pass is on %s"
                   % (repo, n, head[:7], ", ".join(old)))
    return out


def scan(t):
    findings = []
    try:
        gh = GitHub()
    except ScanError as e:
        return ["scan error: %s" % e]
    try:
        for name, fn in (("said-i-would", lambda: check_said(gh, t)),):
            try:
                findings += fn()
            except ScanError as e:
                findings.append("scan error: %s: %s" % (name, e))
        for repo in REPOS:
            lines = ledger(repo)
            heads = passed_heads(lines, repo)
            findings += check_ledger_times(t, repo, lines)
            for name, fn in (("merges", lambda: check_merges(gh, t, repo, heads)),
                             ("open pull requests", lambda: check_moved_heads(gh, repo, heads))):
                try:
                    findings += fn()
                except ScanError as e:
                    findings.append("scan error: %s %s: %s" % (repo, name, e))
    finally:
        gh.close()
    return sorted(set(findings))


# --- Report, memory and the wake -------------------------------------------------------------------------------

def post(count):
    """The wake: one fixed-format comment through checkpoint-note. Returns its exit code."""
    return subprocess.run([os.path.join(LIBEXEC, "checkpoint-note.sh"), "post", str(min(count, MAX_POST))]).returncode


def run():
    state_dir = os.path.join(WORK, "state")
    os.makedirs(state_dir, exist_ok=True)
    lock = open(os.path.join(state_dir, "checkpoint-scan.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("checkpoint-scan: another run is going")
        return 0
    t = now()
    findings = scan(t)
    statef = os.path.join(state_dir, "checkpoint-scan.json")
    try:
        last = json.load(open(statef))
    except (OSError, ValueError):
        last = {}
    digest = hashlib.sha256("\n".join(findings).encode()).hexdigest() if findings else ""
    posted = last.get("posted", "")
    if not findings:
        print("checkpoint-scan: no findings at %s" % iso(t))
        posted = ""
        wake = "none"
    else:
        print("checkpoint-scan: %d finding(s) at %s" % (len(findings), iso(t)))
        for f in findings:
            print("finding: " + f)
        if digest == posted:
            wake = "same report as the last one posted; not posted again"
        else:
            rc = post(len(findings))
            if rc == 0:
                posted, wake = digest, "posted"
            else:
                wake = "checkpoint-note failed (rc %d); the next run tries again" % rc
        print("checkpoint-scan: wake: " + wake)
    report = {"time": iso(t), "findings": findings, "posted": posted, "wake": wake}
    tmp = statef + ".part"
    with open(tmp, "w") as f:
        json.dump(report, f, indent=1, sort_keys=True)
        f.write("\n")
    os.replace(tmp, statef)
    subprocess.run(["logger", "-t", "checkpoint-scan", "%d finding(s); wake: %s" % (len(findings), wake)],
                   capture_output=True)
    return 3 if findings else 0


def show():
    statef = os.path.join(WORK, "state", "checkpoint-scan.json")
    try:
        r = json.load(open(statef))
    except (OSError, ValueError):
        print("checkpoint-scan: no scan yet")
        return 0
    print("checkpoint-scan: last scan at %s, %d finding(s); wake: %s" % (r.get("time"), len(r.get("findings", [])), r.get("wake")))
    for f in r.get("findings", []):
        print("finding: " + f)
    return 0


def main(argv):
    if argv == ["run"]:
        return run()
    if argv == ["show"]:
        return show()
    print("usage: checkpoint-scan run | show", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
