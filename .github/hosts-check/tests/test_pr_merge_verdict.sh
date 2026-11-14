#!/usr/bin/env bash
# pr-merge-verdict.py: the merge sweep's verdict (D-0042 rules 2 to 4, 11). Fixture directories stand in for GitHub's JSON.
# Each guard has a mutation: the test copies the script with that guard removed and must then see the scenario go wrong.
# Usage: .github/hosts-check/tests/test_pr_merge_verdict.sh   (needs python3)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
exec python3 -I - "$root/hosts/ansible/roles/agent_box/files/pr-merge-verdict.py" <<'PY'
import json, os, shutil, subprocess, sys, tempfile
SRC = sys.argv[1]
FULL, H, ME, PR = "jonhill90/central-hub", "a" * 40, "b" * 40, 7
ROLES = ["reviewer", "council-a", "council-b", "council-c"]
fails = 0
tmp = tempfile.mkdtemp()

def ledger(path, roles, head=H, pr=PR, full=FULL):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for r in roles:
            f.write(json.dumps({"role": r, "repo": full, "pr": pr, "head": head, "relay_ref": "cmsg_ABCDEFGHIJ", "relay_time": "2026-11-14T13:00:00Z", "recorder": "orchestrator", "box_time": "2026-11-14T13:00:01Z"}) + "\n")

def fx(files, roles=ROLES, pr_over=None, checks=None, base_status=None, head_text=None, base_text=None, cmp_head=None, approved=None, approved_roles=ROLES, raw_ledger=None):
    d = tempfile.mkdtemp(dir=tmp)
    pr = {"state": "open", "draft": False, "base": {"ref": "main", "sha": "c" * 40}, "head": {"sha": H}, "mergeable": True, "mergeable_state": "clean"}
    pr.update(pr_over or {})
    json.dump(pr, open(d + "/pr.json", "w"))
    json.dump([{"filename": f} for f in files], open(d + "/files.json", "w"))
    json.dump(checks or {"total_count": 1, "check_runs": [{"name": "docs", "status": "completed", "conclusion": "success"}]}, open(d + "/checks.json", "w"))
    json.dump({}, open(d + "/status.json", "w"))
    if raw_ledger is not None:
        open(d + "/ledger.jsonl", "w").write(raw_ledger)
    elif roles is not None:
        ledger(d + "/ledger.jsonl", roles)
    for side, text in (("head", head_text), ("base", base_text)):
        os.makedirs(d + "/content/" + side, exist_ok=True)
        if text:
            for name, body in text.items():
                open(d + "/content/%s/%s" % (side, name.replace("/", "%2F")), "w").write(body)
    if cmp_head is not None: json.dump(cmp_head, open(d + "/compare-head.json", "w"))
    if approved:
        os.makedirs(d + "/approved")
        json.dump(approved, open(d + "/approved/%s.compare.json" % ME, "w"))
        if approved_roles is not None: ledger(d + "/approved/%s.jsonl" % ME, approved_roles, head=ME, pr=1)
    return d

def run(d, script=SRC):
    r = subprocess.run([sys.executable, "-I", script, FULL, str(PR), H, d], capture_output=True, text=True)
    return r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "NO OUTPUT " + r.stderr[-200:]

def mutate(old, new):
    s = open(SRC).read()
    assert old in s, old
    p = os.path.join(tmp, "mut%d.py" % len(os.listdir(tmp)))
    open(p, "w").write(s.replace(old, new, 1))
    return p

def check(name, got, want, mutant=None, d=None):
    global fails
    ok = got.startswith(want)
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else ": got '%s'" % got))
    fails += not ok
    if mutant:
        m = run(d, mutant)
        bad = m.startswith(want) is False
        # the mutant must change the result for this scenario
        print(("ok   " if bad else "FAIL ") + "mutation: " + name + ("" if bad else ": mutant still says '%s'" % m))
        fails += not bad

DOC = ["docs/runbooks/x.md"]
d = fx(DOC);                                               check("four passes on a green PR is GREEN", run(d), "GREEN")
d = fx(DOC, roles=ROLES[:3]);                              check("three passes is not green", run(d), "NOT GREEN: ledger lacks council-c", mutate('missing = [r for r in ROLES if r not in roles]', 'missing = []'), d)
d = fx(DOC, roles=None);                                   check("no ledger is not green", run(d), "NOT GREEN: no ledger")
d = fx(DOC, raw_ledger='{"role": "reviewer"');             check("a partial ledger line is not green", run(d), "NOT GREEN: ledger ends mid-line")
d = fx(DOC, raw_ledger='not json\n');                      check("a ledger line that is not JSON is not green", run(d), "NOT GREEN: ledger line 1 is not JSON")
d = fx(DOC, raw_ledger='{"role": "boss", "repo": "%s", "pr": 7, "head": "%s", "relay_ref": "r", "relay_time": "t", "recorder": "x", "box_time": "t"}\n' % (FULL, H)); check("an unknown role is not green", run(d), "NOT GREEN: ledger line 1 has an unknown role")
d = fx(DOC); ledger(d + "/ledger.jsonl", ROLES, head="d" * 40); check("a ledger of another head is not green (no carry-over)", run(d), "NOT GREEN: ledger line 1 does not match", mutate('o.get("head") != head or', 'False or'), d)
d = fx(DOC); ledger(d + "/ledger.jsonl", ROLES, pr=8);        check("a ledger of another PR is not green", run(d), "NOT GREEN: ledger line 1 does not match")
d = fx(DOC, pr_over={"base": {"ref": "dev", "sha": "c" * 40}}); check("a base other than main is not green", run(d), "NOT GREEN: base is dev", mutate('if pr["base"]["ref"] != "main"', 'if False'), d)
d = fx(DOC, pr_over={"draft": True});                      check("a draft is not green", run(d), "NOT GREEN: PR is a draft")
d = fx(DOC, pr_over={"head": {"sha": "e" * 40}});          check("a moved head is not green", run(d), "NOT GREEN: head is eeeeeee")
d = fx(DOC, pr_over={"mergeable_state": "dirty"});         check("a conflict is not green", run(d), "NOT GREEN: GitHub does not report a clean merge")
d = fx(DOC, checks={"total_count": 1, "check_runs": [{"name": "hosts", "status": "completed", "conclusion": "failure"}]}); check("a failed check is not green", run(d), "NOT GREEN: check hosts: failure")
d = fx(DOC, checks={"total_count": 0, "check_runs": []});  check("no check run is not green", run(d), "NOT GREEN: no checks reported")
d = fx([".github/workflows/docs.yml"]);                    check("an edit under .github/ is green with a NOTE", subprocess.run([sys.executable, "-I", SRC, FULL, str(PR), H, d], capture_output=True, text=True).stdout, "NOTE: this PR edits 1 files under .github/")
# Rule 11: the guarded files need the owner-tap line, the others do not.
for f in ["docs/decisions/0042-let-the-reviewer.md", "docs/decisions/0034-x.md", "hosts/ansible/roles/agent_box/files/runner-job-started.sh", "hosts/ansible/roles/agent_box/files/pr-merge.sh", "hosts/ansible/roles/agent_box/files/pass-record.sh", "hosts/ansible/roles/agent_box/files/pr-merge-verdict.py", "hosts/ansible/roles/agent_box/templates/pr-merge-sweep.timer.j2"]:
    d = fx([f], head_text={}); check("rule 11 file %s needs the owner tap" % f.split("/")[-1], run(d), "OWNER: rule 11 PR")
    d = fx([f], roles=ROLES + ["owner-tap"]);   check("rule 11 file %s with the tap is GREEN" % f.split("/")[-1], run(d), "GREEN")
d = fx(["hosts/ansible/roles/agent_box/files/pr-merge.sh"]); check("the mutation: dropping the rule 11 list lets it through", run(d), "OWNER", mutate('RULE11 = [re.compile(p) for p in (', 'RULE11 = [re.compile(p) for p in ("^$",)] or ('), d)
d = fx(["docs/decisions/0099-x.md", "CLAUDE.md", "AGENTS.md", "docs/standards/STD-0001.md"], roles=ROLES, head_text={"docs/decisions/0099-x.md": "---\nid: D-0099\nstatus: proposed\nsupersedes: []\n---\nbody\n", "docs/standards/STD-0001.md": "---\nid: STD-0001\nstatus: draft\n---\n"}); check("records, standards, CLAUDE.md and AGENTS.md need no tap", run(d), "GREEN")
d = fx(["docs/decisions/0099-x.md"], head_text={"docs/decisions/0099-x.md": "---\nid: D-0099\nstatus: proposed\nsupersedes: [D-0042]\n---\nbody\n"}); check("a record that supersedes D-0042 needs the tap", run(d), "OWNER: rule 11 PR")
d = fx(["docs/decisions/0099-x.md"], head_text={"docs/decisions/0099-x.md": "---\nid: D-0099\nstatus: proposed\nsupersedes:\n  - D-0034\n---\nbody\n"}); check("a block-list supersedes of D-0034 needs the tap", run(d), "OWNER: rule 11 PR")
d = fx(["docs/decisions/0099-x.md"], head_text={"docs/decisions/0099-x.md": "---\nid: D-0099\nstatus: proposed\nsupersedes: []\n---\nThis amends rule 2 of D-0042.\n"}); check("a record whose body amends D-0042 needs the tap", run(d), "OWNER: rule 11 PR")
d = fx(["docs/decisions/0099-x.md"], head_text={"docs/decisions/0099-x.md": "---\nid: D-0099\nstatus: proposed\nsupersedes: []\n---\nThis amends rule 2 of this record. Much later, after a very long stretch of unrelated text that goes on, D-0042 is mentioned.\n"}); check("amend far from D-0042 is not caught", run(d), "GREEN")
# Fold-in (D-0042 rule 3).
def rec(status, extra="", ident="D-0099"):
    return "---\nid: %s\nstatus: %s\ndate: 2026-11-14\nsupersedes: []\naccepted-evidence:\n  approved-by: agents\n  approved-at: 2026-11-14T10:00:00Z\n  approved-commit: %s\n%s---\nbody\n" % (ident, status, ME, extra)
REC = "docs/decisions/0099-x.md"
body_patch = "@@ -1,3 +1,5 @@\n+Some body line\n+Another body line\n"
def cmp_(extra_files=(), status_line=True, patch=body_patch):
    pt = patch + ("+status: accepted\n-status: proposed\n+  approved-by: agents\n" if status_line else "")
    return {"files": [{"filename": REC, "patch": pt, "changes": 3}] + [{"filename": n, "patch": p, "changes": 1} for n, p in extra_files]}
base = rec("proposed").replace("approved-by: agents", "approved-by: nobody")
d = fx([REC], head_text={REC: rec("accepted")}, base_text={REC: base}, cmp_head=cmp_(), approved=cmp_(status_line=False));
check("a fold-in whose net change matches the approved commit is GREEN", run(d), "GREEN")
d = fx([REC], head_text={REC: rec("accepted")}, base_text={REC: base}, cmp_head=cmp_(extra_files=[("docs/other.md", "@@\n+sneaked in\n")]), approved=cmp_(status_line=False))
check("an extra changed file beyond the approved commit refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: the PR's net change differs", mutate('if diff:', 'if False:'), d)
d = fx([REC], head_text={REC: rec("accepted")}, base_text={REC: base}, cmp_head=cmp_(patch=body_patch + "+one more body line\n"), approved=cmp_(status_line=False))
check("an extra changed line in the record refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: the PR's net change differs")
d = fx([REC], head_text={REC: rec("accepted")}, base_text={REC: base}, cmp_head=cmp_(patch="@@ -9,3 +9,5 @@\n context moved\n+Some body line\n+Another body line\n"), approved=cmp_(status_line=False))
check("different context lines (main moved the file) do not refuse", run(d), "GREEN")
d = fx([REC], head_text={REC: rec("accepted")}, base_text={REC: base}, cmp_head=cmp_(), approved=cmp_(status_line=False), approved_roles=ROLES[:3])
check("an approved commit with three passes refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: approved-commit bbbbbbb lacks four passes", mutate('if aerr or any(r not in aroles for r in ROLES):', 'if False:'), d)
d = fx([REC], head_text={REC: rec("accepted")}, base_text={REC: base}, cmp_head=cmp_(), approved=None)
check("a fold-in whose approved commit cannot be read refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: approved-commit bbbbbbb lacks four passes")
d = fx([REC], head_text={REC: rec("accepted").replace("approved-by: agents", "approved-by: owner")}, base_text={REC: base}, cmp_head=cmp_(), approved=cmp_(status_line=False))
check("approved-by other than agents refuses an acceptance", run(d), "NOT GREEN: docs/decisions/0099-x.md: status accepted needs approved-by: agents", mutate('nev.get("approved-by") != "agents"', 'False'), d)
d = fx([REC], head_text={REC: rec("rejected").replace(ME, "short")}, base_text={REC: base}, cmp_head=cmp_(), approved=cmp_(status_line=False))
check("a rejected record without a full approved-commit refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: status rejected needs a full approved-commit")
d = fx([REC], head_text={REC: rec("parked")}, base_text={REC: base}, cmp_head=cmp_(), approved=cmp_(status_line=False))
check("a parked fold-in with a matching net change is GREEN", run(d), "GREEN")
d = fx([REC], head_text={REC: rec("proposed")}, base_text={REC: rec("proposed")});
check("a record that stays proposed has no fold-in check", run(d), "GREEN")
STD = "docs/standards/STD-0007.md"
d = fx([STD], head_text={STD: rec("active", ident="STD-0007")}, base_text={STD: base.replace("D-0099", "STD-0007")}, cmp_head={"files": [{"filename": STD, "patch": "@@\n+x\n", "changes": 1}]}, approved={"files": [{"filename": STD, "patch": "@@\n+x\n", "changes": 1}]})
check("a standard set to active is a fold-in too", run(d), "GREEN")
d = fx([STD], head_text={STD: rec("active", ident="STD-0007")}, base_text={STD: base.replace("D-0099", "STD-0007")}, cmp_head={"files": [{"filename": STD, "patch": "@@\n+x\n+y\n", "changes": 2}]}, approved={"files": [{"filename": STD, "patch": "@@\n+x\n", "changes": 1}]})
check("a standard with an extra line refuses", run(d), "NOT GREEN: docs/standards/STD-0007.md: the PR's net change differs")
d = fx([REC], head_text={REC: rec("accepted")}, base_text={REC: base}, cmp_head=None, approved=cmp_(status_line=False))
check("a missing compare refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: the compare")
d = fx([REC] + ["docs/decisions/%04d-y.md" % i for i in range(25)], head_text={})
check("more than 20 record files are not checked", run(d), "NOT GREEN: more than 20 record")
d = tempfile.mkdtemp(dir=tmp)
check("a missing input is a refusal, not a pass", run(d), "NOT GREEN: could not decide")
shutil.rmtree(tmp)
sys.exit(1 if fails else 0)
PY
