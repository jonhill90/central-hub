#!/usr/bin/env python3
"""The merge sweep's verdict on one pull request (D-0042 rules 2 to 4 and 11). Pure: it reads files and prints.

  pr-merge-verdict.py FULL_NAME PR_NUMBER HEAD_SHA DIR

DIR holds what pr-merge.sh fetched: pr.json files.json checks.json status.json, ledger.jsonl (absent = no ledger),
compare-head.json, content/{base,head}/<path with / as %2F>, approved/<sha>.compare.json and approved/<sha>.jsonl.
Prints NOTE lines, then one last line: GREEN, NOT GREEN: <reasons>, or OWNER: <what needs the owner's tap line>.
Anything it cannot read or parse is a reason, never a pass. Installed root-owned by the agent_box role.
"""
import collections
import json
import os
import re
import sys
import urllib.parse

ROLES = ("reviewer", "council-a", "council-b", "council-c")
ALL_ROLES = ROLES + ("owner-tap",)
RECORD_STATUS = ("accepted", "rejected", "parked")
STANDARD_STATUS = ("active",)
RULE11 = [re.compile(p) for p in (
    r"^docs/decisions/0042-.*\.md$", r"^docs/decisions/0034-.*\.md$",
    r"^hosts/ansible/roles/agent_box/files/(runner-job-started\.sh|pr-merge\.sh|pr-merge-verdict\.py|pass-record\.sh)$",
    r"^hosts/ansible/roles/agent_box/templates/pr-merge-sweep\.(service|timer)\.j2$",
)]
MAX_RECORDS = 20
DROP_TOP = re.compile(r"^[+-](status|date|accepted-evidence):")
DROP_NESTED = re.compile(r"^[+-]  (approved-by|approved-at|approved-commit|approval-ref|approval-names|check|merged):")


def load(d, name):
    with open(os.path.join(d, name)) as f:
        return json.load(f)


def read_ledger(path, full, head, pr=None):
    """Returns (set of roles, lines, error). A ledger that does not parse is an error."""
    if not os.path.isfile(path):
        return set(), [], "no ledger"
    roles, lines = set(), []
    try:
        with open(path) as f:
            raw = f.read()
    except OSError as e:
        return set(), [], "ledger unreadable: %s" % e
    if raw and not raw.endswith("\n"):
        return set(), [], "ledger ends mid-line (partial)"
    for n, line in enumerate(raw.splitlines(), 1):
        try:
            o = json.loads(line)
        except ValueError:
            return set(), [], "ledger line %d is not JSON" % n
        if not isinstance(o, dict) or o.get("role") not in ALL_ROLES:
            return set(), [], "ledger line %d has an unknown role" % n
        if o.get("repo") != full or o.get("head") != head or (pr is not None and o.get("pr") != pr):
            return set(), [], "ledger line %d does not match this repository, PR and head" % n
        for k in ("relay_ref", "relay_time", "recorder", "box_time"):
            if not isinstance(o.get(k), str) or not o[k]:
                return set(), [], "ledger line %d lacks %s" % (n, k)
        roles.add(o["role"])
        lines.append(o)
    return roles, lines, None


def front_matter(text):
    """Top-level keys and the accepted-evidence keys, from the leading --- block."""
    top, ev = {}, {}
    if not text or not text.startswith("---"):
        return top, ev, ""
    parts = text.split("\n---", 1)
    block = parts[0].splitlines()[1:]
    cur = None
    for line in block:
        m = re.match(r"^([A-Za-z-]+):\s*(.*)$", line)
        if m:
            cur = m.group(1)
            top[cur] = m.group(2).strip().strip('"')
            continue
        m = re.match(r"^  ([A-Za-z-]+):\s*(.*)$", line)
        if m and cur == "accepted-evidence":
            ev[m.group(1)] = m.group(2).strip().strip('"')
        elif cur == "supersedes" and re.match(r"^\s+-\s", line):
            top["supersedes"] += " " + line.strip()
    return top, ev, "\n".join(block)


def changed_lines(patch, record_id, is_index, is_record):
    c = collections.Counter()
    for line in (patch or "").splitlines():
        if not line or line[0] not in "+-":
            continue
        if is_record and (DROP_TOP.match(line) or DROP_NESTED.match(line)):
            continue
        if is_index and record_id and record_id in line:
            continue
        c[line] += 1
    return c


def net_change(cmp_json, record_path, record_id):
    files = cmp_json.get("files")
    if not isinstance(files, list) or len(files) >= 300:
        return None, "compare is missing or has 300 or more files"
    out = {}
    for f in files:
        if "patch" not in f and f.get("changes", 0) != 0:
            return None, "no patch for %s" % f.get("filename")
        name = f["filename"]
        idx = name in ("docs/decisions/README.md", "docs/standards/README.md")
        c = changed_lines(f.get("patch"), record_id, idx, name == record_path)
        if c:
            out[name] = c
    return out, None


def main():
    full, pr_s, head, d = sys.argv[1:5]
    pr_no = int(pr_s)
    why, notes = [], []
    pr, files, checks, status = (load(d, n + ".json") for n in ("pr", "files", "checks", "status"))
    if pr.get("state") != "open": why.append("PR is not open")
    if pr.get("draft"): why.append("PR is a draft")
    if pr["base"]["ref"] != "main": why.append("base is %s, not main" % pr["base"]["ref"])
    if pr["head"]["sha"] != head: why.append("head is %s, not the one named" % pr["head"]["sha"][:7])
    if pr.get("mergeable") is not True or pr.get("mergeable_state") not in ("clean", "has_hooks"):
        why.append("GitHub does not report a clean merge (mergeable=%s, state=%s)" % (pr.get("mergeable"), pr.get("mergeable_state")))
    if len(files) >= 100: why.append("100 or more changed files; not checked")
    runs = checks.get("check_runs", [])
    if checks.get("total_count", len(runs)) != len(runs): why.append("read %d of %d check runs; not checked" % (len(runs), checks["total_count"]))
    if not runs and not status.get("statuses"): why.append("no checks reported on this head")
    for r in runs:
        if r["status"] != "completed": why.append("check %s is %s" % (r["name"], r["status"]))
        elif r["conclusion"] not in ("success", "skipped"): why.append("check %s: %s" % (r["name"], r["conclusion"]))
    if status.get("statuses") and status.get("state") != "success": why.append("commit status is %s" % status.get("state"))

    names = [f["filename"] for f in files]
    gh = [n for n in names if n.startswith(".github/")]
    if gh:
        notes.append("NOTE: this PR edits %d files under .github/; green is from the PR's own copy of them (%s)" % (len(gh), ", ".join(gh[:5])))

    # The ledger: four passes for this exact head.
    roles, lines, err = read_ledger(os.path.join(d, "ledger.jsonl"), full, head, pr_no)
    if err: why.append(err)
    missing = [r for r in ROLES if r not in roles]
    if not err and missing: why.append("ledger lacks " + ", ".join(missing))

    central = full == "jonhill90/central-hub"
    # Rule 11 files and the supersede/amend text catch.
    rule11 = [n for n in names if central and any(p.match(n) for p in RULE11)] if central else []
    rec_files = [n for n in names if central and re.match(r"^docs/(decisions|standards)/[^/]+\.md$", n) and not n.endswith("README.md")]
    if len(rec_files) > MAX_RECORDS:
        why.append("more than %d record or standard files changed; not checked" % MAX_RECORDS)
        rec_files = rec_files[:MAX_RECORDS]
    cdir = os.path.join(d, "content")

    def content(side, path):
        p = os.path.join(cdir, side, urllib.parse.quote(path, safe=""))
        try:
            with open(p) as f:
                return f.read()
        except OSError:
            return None

    fstatus = {f["filename"]: f.get("status", "") for f in files}
    # A changed record or standard with no head content is a refusal unless GitHub says the PR removes it.
    for n in rec_files:
        if fstatus.get(n) != "removed" and content("head", n) is None:
            why.append("%s: its content at the head could not be read" % n)
    rec_files = [n for n in rec_files if fstatus.get(n) != "removed"]
    for n in rec_files:
        if not n.startswith("docs/decisions/"): continue
        text = content("head", n)
        if text is None: continue
        top, _ev, _blk = front_matter(text)
        sup = top.get("supersedes", "")
        amend = re.search(r"(amend\w*.{0,40}D-00(42|34)|D-00(42|34).{0,40}amend\w*)", text, re.I | re.S)
        if re.search(r"D-00(42|34)", sup) or amend:
            rule11.append(n + " (names D-0042 or D-0034 as superseded or amended)")

    # The fold-in case (D-0042 rule 3): a status change to accepted/rejected/parked/active.
    for n in rec_files:
        is_std = n.startswith("docs/standards/")
        want = STANDARD_STATUS if is_std else RECORD_STATUS
        new = content("head", n)
        old = content("base", n)
        if new is None: continue
        ntop, nev, _ = front_matter(new)
        otop, _oev, _ = front_matter(old) if old else ({}, {}, "")
        st = ntop.get("status", "")
        if st not in want or (old is not None and otop.get("status") == st):
            continue
        if st in ("accepted", "active") and nev.get("approved-by") != "agents":
            why.append("%s: status %s needs approved-by: agents" % (n, st)); continue
        ac = nev.get("approved-commit", "")
        if not re.match(r"^[0-9a-f]{40}$", ac):
            why.append("%s: status %s needs a full approved-commit" % (n, st)); continue
        aroles, _al, aerr = read_ledger(os.path.join(d, "approved", ac + ".jsonl"), full, ac)
        if aerr or any(r not in aroles for r in ROLES):
            why.append("%s: approved-commit %s lacks four passes (%s)" % (n, ac[:7], aerr or "incomplete")); continue
        try:
            acmp = load(os.path.join(d, "approved"), ac + ".compare.json")
            hcmp = load(d, "compare-head.json")
        except (OSError, ValueError):
            why.append("%s: the compare for approved-commit or head could not be read" % n); continue
        rid = ntop.get("id", "")
        a, e1 = net_change(acmp, n, rid)
        h, e2 = net_change(hcmp, n, rid)
        if e1 or e2:
            why.append("%s: %s" % (n, e1 or e2)); continue
        diff = sorted(f for f in set(a) | set(h) if a.get(f, collections.Counter()) != h.get(f, collections.Counter()))
        if diff:
            why.append("%s: the PR's net change differs from approved-commit %s in %s" % (n, ac[:7], ", ".join(diff[:3])))

    needs_tap = bool(rule11)
    tap_missing = needs_tap and "owner-tap" not in roles
    if tap_missing:
        msg = "rule 11 PR (%s) needs an owner-tap line" % ", ".join(rule11[:3])
        if why: why.append(msg)
        else:
            for x in notes: print(x)
            print("OWNER: " + msg)
            return
    for x in notes: print(x)
    print("NOT GREEN: " + "; ".join(why) if why else "GREEN")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # a failed read is never a pass
        print("NOT GREEN: could not decide (%s: %s)" % (type(e).__name__, e))
