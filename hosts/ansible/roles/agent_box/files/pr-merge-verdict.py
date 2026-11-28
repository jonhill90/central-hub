#!/usr/bin/env python3
"""The merge sweep's verdict on one pull request (D-0042 rules 2 to 4). Pure: it reads files and prints.

  pr-merge-verdict.py FULL_NAME PR_NUMBER HEAD_SHA DIR

DIR holds what pr-merge.sh fetched: pr.json files.json checks.json status.json, ledger.jsonl (absent = no ledger),
compare-head.json, content/{base,head}/<path with / as %2F>, approved/<sha>.compare.json and approved/<sha>.jsonl.
Prints NOTE lines, then one last line: GREEN or NOT GREEN: <reasons>.
Anything it cannot read or parse is a reason, never a pass. Installed root-owned by the agent_box role.
"""
import collections
import json
import os
import re
import sys
import urllib.parse

# The reviewer's pass is the one an exact head needs (the owner's order of 2026-11-18 00:03 UTC dropped the three councils).
# A ledger line of an earlier role still parses, so a head recorded before that order is read, not refused.
ROLES = ("reviewer",)
ALL_ROLES = ROLES + ("council-a", "council-b", "council-c", "owner-tap")
RECORD_STATUS = ("accepted", "rejected", "parked")
STANDARD_STATUS = ("active",)
MAX_RECORDS = 20

# Paths that still need the reviewer's pass for the exact head: the kinds the owner keeps (firewall, tailnet, secrets,
# access rights, the agents' own rules), the workflows, the Mac's command wrappers and the Proxmox host job (root on the
# host, run on the agents' pass). Any other green PR merges on its checks alone (the owner's order of 2026-11-23,
# 00:50:45 UTC; the list is an agent pick, D-0065). The agent box role is not listed: box-apply still installs
# a change to its limits only on the reviewer's digest pass (D-0044), so a merge-time pass on it was the same check twice.
GUARDED_ANY = (".github/", "AGENTS.md", "CLAUDE.md", "SECURITY.md")
GUARDED_CENTRAL = ("hosts/wrappers/", "hosts/ansible/playbooks/proxmox-proxy.yml", "hosts/ansible/roles/proxmox_proxy/",
                   "hosts/ansible/roles/k8s_identity/")
GUARDED_WORDS = ("opnsense", "tailnet", "tailscale", "firewall", "sops", "secret", "sudoers", "openbao", "realm")
# An added or removed line that handles a secret or a password guards its file whatever the file's name.
GUARDED_LINE = re.compile(r"ExternalSecret|secretKeyRef|kind:\s*Secret\b|password", re.I)


def guarded_file(full, f):
    """A changed file from GitHub's PR files list: guarded by its path, or by a changed line that touches a secret.
    A file GitHub sends no patch for (too large, or binary) counts as guarded when it has changes."""
    if guarded(full, f["filename"]):
        return True
    patch = f.get("patch")
    if patch is None:
        return f.get("changes", 1) != 0
    # The notebook's notes are prose that names these words ("no password is in it"); a note holds no secret to guard, and a
    # secret written into one is stopped by rule 4 and the notebook's checks. Its other file types keep the line check.
    if full == "jonhill90/agent-notebook" and f["filename"].endswith(".md"):
        return False
    return any(l[:1] in "+-" and not l.startswith(("+++", "---")) and GUARDED_LINE.search(l) for l in patch.splitlines())


def guarded(full, name):
    if name.startswith(GUARDED_ANY) or name.rsplit("/", 1)[-1] in GUARDED_ANY:
        return True
    if full == "jonhill90/central-hub-app":
        return name.startswith("docs/evidence/")   # its screenshot allow-list and images
    if full != "jonhill90/central-hub":
        return False
    low = name.lower()
    return name.startswith(GUARDED_CENTRAL) or any(w in low for w in GUARDED_WORDS)


DROP_TOP = re.compile(r"^[+-](status|date|accepted-evidence):")
DROP_NESTED = re.compile(r"^[+-]  (approved-by|approved-at|approved-commit|approval-ref|approval-names|check|merged):")


def load(d, name):
    with open(os.path.join(d, name)) as f:
        return json.load(f)


def superseded(runs, d, head):
    """Ids of check runs that a newer, passing run of the same Actions job replaced: same workflow, same event, same
    job name, this head. Editing a PR description runs spec-line again (it reads the description), and the older run's failure
    stays on the commit, so only the newest run of a job decides. A run with no workflow run behind it (CodeQL, another
    app) is never dropped, and without a full runs.json (the head's workflow runs) nothing is dropped."""
    try:
        wr = load(d, "runs.json")
        wruns = wr["workflow_runs"]
        if wr.get("total_count", len(wruns)) != len(wruns): return set()
        job = {w["check_suite_id"]: (w["workflow_id"], w["event"]) for w in wruns if w.get("head_sha") == head}
        newest = {}
        for r in runs:
            k = job.get((r.get("check_suite") or {}).get("id"))
            if k is None or not isinstance(r.get("id"), int): continue
            k = k + (r["name"],)
            if k not in newest or r["id"] > newest[k]["id"]: newest[k] = r
        out = set()
        for r in runs:
            k = job.get((r.get("check_suite") or {}).get("id"))
            if k is None or not isinstance(r.get("id"), int): continue
            n = newest[k + (r["name"],)]
            # Only a newer run that passed replaces an older one: a skip counts as green only when the workflow
            # skips on purpose (D-0031 rule 1), so a newer skipped or pending run never hides an older failure.
            if n["id"] != r["id"] and n.get("status") == "completed" and n.get("conclusion") == "success": out.add(r["id"])
        return out
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return set()


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
    print("NOTE: verdict v2")   # a fixed marker on every run: the ledger is checked (older pr-merge: no ledger)
    why, notes = [], []
    pr, files, checks, status = (load(d, n + ".json") for n in ("pr", "files", "checks", "status"))
    if pr.get("state") != "open": why.append("PR is not open")
    if pr.get("draft"): why.append("PR is a draft")
    if pr["base"]["ref"] != "main": why.append("base is %s, not main" % pr["base"]["ref"])
    if pr["head"]["sha"] != head: why.append("head is %s, not the one named" % pr["head"]["sha"][:7])
    if pr.get("mergeable") is not True or pr.get("mergeable_state") not in ("clean", "has_hooks"):
        why.append("GitHub does not report a clean merge (mergeable=%s, state=%s)" % (pr.get("mergeable"), pr.get("mergeable_state")))
        # Explanation only: it adds to this reason and never turns a clean merge into a refusal. main requires signatures, and GitHub
        # counts the PR's own commits, so an unverified one blocks the merge; updating the branch does not fix that.
        try:
            bad = [c for c in load(d, "commits.json") if not ((c.get("commit") or {}).get("verification") or {}).get("verified")]
        except (OSError, ValueError, TypeError, AttributeError):
            bad = []
        for c in bad[:5]:
            v = (c.get("commit") or {}).get("verification") or {}
            why.append("commit %s is not verified (%s): GitHub blocks the merge on it; re-make the head as verified commits, updating the branch will not fix it" % (str(c.get("sha", "?"))[:7], v.get("reason", "unknown")))
    if len(files) >= 3000: why.append("3000 or more changed files; GitHub lists no more, so the rest are not checked")
    runs = checks.get("check_runs", [])
    if checks.get("total_count", len(runs)) != len(runs): why.append("read %d of %d check runs; not checked" % (len(runs), checks["total_count"]))
    if not runs and not status.get("statuses"): why.append("no checks reported on this head")
    gone = superseded(runs, d, head)
    if gone: notes.append("NOTE: %d check run(s) replaced by a newer passing run of the same job on this head, not counted: %s" % (len(gone), ", ".join(sorted("%s %s" % (r["name"], r.get("conclusion")) for r in runs if r.get("id") in gone))))
    for r in runs:
        if r.get("id") in gone: continue
        if r["status"] != "completed": why.append("check %s is %s" % (r["name"], r["status"]))
        elif r["conclusion"] not in ("success", "skipped"): why.append("check %s: %s" % (r["name"], r["conclusion"]))
    if status.get("statuses") and status.get("state") != "success": why.append("commit status is %s" % status.get("state"))

    names = [f["filename"] for f in files]
    gh = [n for n in names if n.startswith(".github/")]
    if gh:
        notes.append("NOTE: this PR edits %d files under .github/; green is from the PR's own copy of them (%s)" % (len(gh), ", ".join(gh[:5])))

    # The ledger: the reviewer's pass for this exact head, needed only when a guarded path changed or a record's status
    # changes (decided below, after the record checks).
    roles, lines, err = read_ledger(os.path.join(d, "ledger.jsonl"), full, head, pr_no)
    hit = [f["filename"] for f in files if guarded_file(full, f)]
    # Only a PR whose head branch is in this repository may merge without a pass: a fork's PR is someone else's code.
    if ((pr.get("head") or {}).get("repo") or {}).get("full_name") != full:
        hit.append("(head branch is not in %s)" % full)

    central = full == "jonhill90/central-hub"
    # The Proxmox host job runs this playbook and role as root on the host on the agents' pass (pick 241).
    hostjob = [n for n in names if central and (n == "hosts/ansible/playbooks/proxmox-proxy.yml" or n.startswith("hosts/ansible/roles/proxmox_proxy/"))]
    if hostjob:
        notes.append("NOTE: this PR edits what the Proxmox host job runs as root on the host (%s); check that no firewall, delete or secret step is in it" % ", ".join(hostjob[:5]))
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
        hit.append(n)   # a status change (accepting a record) always needs the reviewer's pass
        if st in ("accepted", "active") and nev.get("approved-by") == "owner":
            # The owner's own card tap: the PR's ledger holds an owner-tap line whose relay ref is the record's approval-ref, and
            # the PR changes nothing but the acceptance fields (no approved-commit and no passes on one are needed).
            ref = nev.get("approval-ref", "")
            if not ref or not any(l.get("role") == "owner-tap" and l.get("relay_ref") == ref for l in lines):
                why.append("%s: approved-by owner needs an owner-tap line whose relay ref is its approval-ref" % n); continue
            try:
                hcmp = load(d, "compare-head.json")
            except (OSError, ValueError):
                why.append("%s: the compare for head could not be read" % n); continue
            h, e2 = net_change(hcmp, n, ntop.get("id", ""))
            ac = nev.get("approved-commit", "")
            if re.match(r"^[0-9a-f]{40}$", ac):
                # The owner tapped a card that named this content commit: the PR's net change must equal that commit's, apart from
                # the acceptance fields and the index row (the agents' path's compare). No passes on it are needed.
                try:
                    acmp = load(os.path.join(d, "approved"), ac + ".compare.json")
                except (OSError, ValueError):
                    why.append("%s: the compare for approved-commit %s could not be read" % (n, ac[:7])); continue
                a, e1 = net_change(acmp, n, ntop.get("id", ""))
                if e1 or e2:
                    why.append("%s: %s" % (n, e1 or e2)); continue
                odiff = sorted(f for f in set(a) | set(h) if a.get(f, collections.Counter()) != h.get(f, collections.Counter()))
                if odiff:
                    why.append("%s: the PR's net change differs from the owner-approved commit %s in %s" % (n, ac[:7], ", ".join(odiff[:3]))); continue
            elif e2 or h:
                why.append("%s: approved-by owner allows only the acceptance fields to change (%s)" % (n, e2 or ", ".join(sorted(h)[:3]))); continue
            notes.append("NOTE: %s is accepted on the owner's card tap %s" % (n, ref))
            continue
        if st in ("accepted", "active") and nev.get("approved-by") != "agents":
            why.append("%s: status %s needs approved-by: agents or owner" % (n, st)); continue
        ac = nev.get("approved-commit", "")
        if not re.match(r"^[0-9a-f]{40}$", ac):
            why.append("%s: status %s needs a full approved-commit" % (n, st)); continue
        aroles, _al, aerr = read_ledger(os.path.join(d, "approved", ac + ".jsonl"), full, ac)
        if aerr or any(r not in aroles for r in ROLES):
            why.append("%s: approved-commit %s lacks the reviewer's pass (%s)" % (n, ac[:7], aerr or "incomplete")); continue
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

    if hit:
        notes.append("NOTE: guarded paths changed, so the reviewer's pass is needed: %s" % ", ".join(hit[:5]))
        if err: why.append(err)
        missing = [r for r in ROLES if r not in roles]
        if not err and missing: why.append("ledger lacks " + ", ".join(missing))
    else:
        notes.append("NOTE: no guarded path changed; green checks and a clean merge are enough")
        if err and err != "no ledger": why.append(err)

    for x in notes: print(x)
    if not why:
        # Printed on every GREEN so a caller can tell this verdict (ledger checked) from an older pr-merge's.
        print("LEDGER: " + " ".join(r for r in ROLES if r in roles))
    print("NOT GREEN: " + "; ".join(why) if why else "GREEN")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # a failed read is never a pass
        print("NOT GREEN: could not decide (%s: %s)" % (type(e).__name__, e))
