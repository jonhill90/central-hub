"""Decide whether the merge job may squash-merge one pull request (D-0042 rule 2).

Usage: python3 -I verdict.py HEAD_SHA FOLDER
FOLDER holds pr.json, files.json, checks.json and status.json, as GitHub's REST API returns them.
Prints GREEN, or NOT GREEN with every reason, and exits 0 for GREEN and 1 otherwise.
"""

import json
import sys


def verdict(head, pr, files, checks, status):
    """Return the reasons a merge must not go ahead; an empty list means green."""
    why = []
    if pr.get("state") != "open":
        why.append("the PR is not open")
    if pr.get("draft"):
        why.append("the PR is a draft")
    if pr.get("base", {}).get("ref") != "main":
        why.append("the PR does not target main")
    if pr.get("head", {}).get("sha") != head:
        why.append("the head is %s, not the one named" % str(pr.get("head", {}).get("sha"))[:7])
    if pr.get("mergeable") is not True or pr.get("mergeable_state") not in ("clean", "has_hooks"):
        why.append("GitHub does not report a clean merge (mergeable=%s, state=%s)"
                   % (pr.get("mergeable"), pr.get("mergeable_state")))
    if len(files) >= 100:
        why.append("100 or more changed files; not checked")
    runs = checks.get("check_runs", [])
    if checks.get("total_count", len(runs)) != len(runs):
        why.append("read %d of %d check runs; not checked" % (len(runs), checks.get("total_count")))
    if not runs and not status.get("statuses"):
        why.append("no checks reported on this head")
    for run in runs:
        if run.get("status") != "completed":
            why.append("check %s is %s" % (run.get("name"), run.get("status")))
        elif run.get("conclusion") not in ("success", "skipped"):
            why.append("check %s: %s" % (run.get("name"), run.get("conclusion")))
    if status.get("statuses") and status.get("state") != "success":
        why.append("commit status is %s" % status.get("state"))
    return why


def main():
    head, folder = sys.argv[1], sys.argv[2]
    pr, files, checks, status = (json.load(open("%s/%s.json" % (folder, name)))
                                 for name in ("pr", "files", "checks", "status"))
    why = verdict(head, pr, files, checks, status)
    print("NOT GREEN: " + "; ".join(why) if why else "GREEN")
    sys.exit(1 if why else 0)


if __name__ == "__main__":
    main()
