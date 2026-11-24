#!/usr/bin/env python3
"""Time from PR open to merge for every PR merged in the last N hours, and flag a slow one (AGENTS.md rules 2 and 7).

  lead-time.py OWNER/REPO [HOURS] [LIMIT_MINUTES]      reads GITHUB_TOKEN from the environment; changes nothing

An unguarded PR (pr_guarded() below: pr-merge-verdict.py's guarded_file() on each file, or a fork head) that took longer than LIMIT_MINUTES (default 30) from open, or from leaving
draft when GitHub says so, to merge is SLOW. Prints a Markdown table, then one last line: FAST or SLOW: <PR numbers>.
Exits 1 on SLOW so the scheduled run fails and GitHub tells the owner.
"""
import datetime as dt
import importlib.util
import json
import os
import sys
import urllib.request

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "verdict", os.path.join(here, "../../hosts/ansible/roles/agent_box/files/pr-merge-verdict.py"))
verdict = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verdict)


def get(url):
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json",
                                               "Authorization": "Bearer " + os.environ.get("GITHUB_TOKEN", "")})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def t(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def ready_at(full, pr):
    """When the PR left draft, if its timeline says so; else when it was opened."""
    try:
        ev = get("https://api.github.com/repos/%s/issues/%d/events?per_page=100" % (full, pr["number"]))
        r = [e["created_at"] for e in ev if e.get("event") == "ready_for_review"]
        if r: return t(r[-1])
    except Exception:
        pass
    return t(pr["created_at"])


def pr_guarded(full, pr, files):
    """The verdict's own test: a guarded path or a changed secret line in any file, or a head branch from a fork."""
    if ((pr.get("head") or {}).get("repo") or {}).get("full_name") != full:
        return True
    return any(verdict.guarded_file(full, f) for f in files)


def main():
    full = sys.argv[1]
    hours = float(sys.argv[2]) if len(sys.argv) > 2 else 24
    limit = float(sys.argv[3]) if len(sys.argv) > 3 else 30
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=hours)
    prs = get("https://api.github.com/repos/%s/pulls?state=closed&sort=updated&direction=desc&per_page=100" % full)
    rows, slow = [], []
    for pr in prs:
        if not pr.get("merged_at") or t(pr["merged_at"]) < since: continue
        files = get("https://api.github.com/repos/%s/pulls/%d/files?per_page=100" % (full, pr["number"]))
        g = pr_guarded(full, pr, files)
        mins = (t(pr["merged_at"]) - ready_at(full, pr)).total_seconds() / 60
        bad = not g and mins > limit
        if bad: slow.append(pr["number"])
        rows.append((pr["number"], round(mins), "guarded" if g else "plain", "SLOW" if bad else "", pr["title"][:70]))
    print("| PR | minutes open to merge | kind | | title |\n|---|---|---|---|---|")
    for r in sorted(rows): print("| #%d | %d | %s | %s | %s |" % r)
    print("SLOW: " + " ".join("#%d" % n for n in slow) if slow else "FAST")
    return 1 if slow else 0


if __name__ == "__main__":
    sys.exit(main())
