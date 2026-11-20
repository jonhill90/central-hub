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

def ledger(path, roles, head=H, pr=PR, full=FULL, refs=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for r in roles:
            f.write(json.dumps({"role": r, "repo": full, "pr": pr, "head": head, "relay_ref": (refs or {}).get(r, "cmsg_ABCDEFGHIJ"), "relay_time": "2026-11-14T13:00:00Z", "recorder": "orchestrator", "box_time": "2026-11-14T13:00:01Z"}) + "\n")

def fx(files, removed=(), roles=ROLES, pr_over=None, checks=None, base_status=None, head_text=None, base_text=None, cmp_head=None, approved=None, approved_roles=ROLES, raw_ledger=None, refs=None):
    d = tempfile.mkdtemp(dir=tmp)
    pr = {"state": "open", "draft": False, "base": {"ref": "main", "sha": "c" * 40}, "head": {"sha": H}, "mergeable": True, "mergeable_state": "clean"}
    pr.update(pr_over or {})
    json.dump(pr, open(d + "/pr.json", "w"))
    json.dump([{"filename": f, "status": "removed" if f in removed else "modified"} for f in files], open(d + "/files.json", "w"))
    json.dump(checks or {"total_count": 1, "check_runs": [{"name": "docs", "status": "completed", "conclusion": "success"}]}, open(d + "/checks.json", "w"))
    json.dump({}, open(d + "/status.json", "w"))
    if raw_ledger is not None:
        open(d + "/ledger.jsonl", "w").write(raw_ledger)
    elif roles is not None:
        ledger(d + "/ledger.jsonl", roles, refs=refs)
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
    ok = (got == want) if isinstance(want, bool) else got.startswith(want)
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else ": got '%s'" % got))
    fails += not ok
    if mutant:
        m = run(d, mutant)
        bad = m.startswith(want) is False
        # the mutant must change the result for this scenario
        print(("ok   " if bad else "FAIL ") + "mutation: " + name + ("" if bad else ": mutant still says '%s'" % m))
        fails += not bad

DOC = ["docs/runbooks/x.md"]
d = fx(DOC, roles=["reviewer"]);                            check("the reviewer's pass alone on a green PR is GREEN", run(d), "GREEN")
d = fx(DOC);                                               check("a ledger that still holds the councils' lines is GREEN too", run(d), "GREEN")
d = fx(DOC, roles=ROLES[1:]);                              check("councils without the reviewer is not green", run(d), "NOT GREEN: ledger lacks reviewer", mutate('missing = [r for r in ROLES if r not in roles]', 'missing = []'), d)
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
d = fx([".github/workflows/docs.yml"]);                    check("an edit under .github/ is green with a NOTE", subprocess.run([sys.executable, "-I", SRC, FULL, str(PR), H, d], capture_output=True, text=True).stdout.replace("NOTE: verdict v2\n", "", 1), "NOTE: this PR edits 1 files under .github/")
d = fx(["hosts/ansible/roles/proxmox_proxy/tasks/main.yml"]);  check("an edit to the host job's role is green with a NOTE", subprocess.run([sys.executable, "-I", SRC, FULL, str(PR), H, d], capture_output=True, text=True).stdout.replace("NOTE: verdict v2\n", "", 1), "NOTE: this PR edits what the Proxmox host job runs")
d = fx(["hosts/ansible/playbooks/proxmox-proxy.yml"]);           check("an edit to the host job's playbook is green with a NOTE", subprocess.run([sys.executable, "-I", SRC, FULL, str(PR), H, d], capture_output=True, text=True).stdout.replace("NOTE: verdict v2\n", "", 1), "NOTE: this PR edits what the Proxmox host job runs")
d = fx(["hosts/ansible/roles/proxmox_proxy/tasks/main.yml"]);  check("the host job's role still merges GREEN", run(d), "GREEN")
# No owner-tap line is needed for any file: the merge guard's own files, D-0042 and D-0034, a record that amends them and the
# role's defaults merge on the reviewer's pass like any other PR (D-0059).
for f in ["docs/decisions/0042-let-the-reviewer.md", "docs/decisions/0034-x.md", "hosts/ansible/roles/agent_box/files/pr-merge.sh", "hosts/ansible/roles/agent_box/files/pr-merge-verdict.py", "hosts/ansible/roles/agent_box/files/pass-record.sh", "hosts/ansible/roles/agent_box/defaults/main.yml"]:
    d = fx([f], head_text={f: "---\nid: D-0042\nstatus: proposed\nsupersedes: []\n---\n"}, base_text={f: "---\nid: D-0042\nstatus: proposed\nsupersedes: []\n---\nold\n"}); check("%s merges on the reviewer's pass with no owner tap" % f.split("/")[-1], run(d), "GREEN")
d = fx(["docs/decisions/0099-x.md"], head_text={"docs/decisions/0099-x.md": "---\nid: D-0099\nstatus: proposed\nsupersedes: [D-0042]\n---\nThis amends rule 2 of D-0042.\n"}); check("a record that supersedes or amends D-0042 merges on the reviewer's pass", run(d), "GREEN")
d = fx(["hosts/ansible/roles/agent_box/files/pr-merge.sh"], roles=ROLES[1:]); check("a guard file still needs the reviewer's pass", run(d), "NOT GREEN: ledger lacks reviewer")
d = fx(DOC); r = subprocess.run([sys.executable, "-I", SRC, FULL, str(PR), H, d], capture_output=True, text=True).stdout
check("every run prints the verdict v2 marker", r, "NOTE: verdict v2")
check("a GREEN prints the role it needs and found", r.replace("NOTE: verdict v2\n", "", 1), "LEDGER: reviewer")
d = fx(DOC, roles=ROLES[1:]); r = subprocess.run([sys.executable, "-I", SRC, FULL, str(PR), H, d], capture_output=True, text=True).stdout
check("a NOT GREEN prints no LEDGER line", "x" + ("bad" if "LEDGER:" in r else "ok"), "xok")
check("a NOT GREEN still prints the verdict v2 marker", r, "NOTE: verdict v2")
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
d = fx([REC], head_text={REC: rec("accepted")}, base_text={REC: base}, cmp_head=cmp_(), approved=cmp_(status_line=False), approved_roles=ROLES[1:])
check("an approved commit without the reviewer's pass refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: approved-commit bbbbbbb lacks the reviewer's pass", mutate('if aerr or any(r not in aroles for r in ROLES):', 'if False:'), d)
d = fx([REC], head_text={REC: rec("accepted")}, base_text={REC: base}, cmp_head=cmp_(), approved=None)
check("a fold-in whose approved commit cannot be read refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: approved-commit bbbbbbb lacks the reviewer's pass")
d = fx([REC], head_text={REC: rec("accepted").replace("approved-by: agents", "approved-by: someone")}, base_text={REC: base}, cmp_head=cmp_(), approved=cmp_(status_line=False))
check("approved-by other than agents or owner refuses an acceptance", run(d), "NOT GREEN: docs/decisions/0099-x.md: status accepted needs approved-by: agents or owner", mutate('nev.get("approved-by") != "agents"', 'False'), d)
# The owner's own card tap (approved-by: owner): an owner-tap line whose relay ref is the approval-ref, and only the acceptance fields change.
TAP = "cmsg_DECIDEEVENT01"
def own(ref=TAP, commit=False):
    t = rec("accepted", extra="  approval-ref: %s\n" % ref).replace("approved-by: agents", "approved-by: owner")
    return t if commit else t.replace("  approved-commit: %s\n" % ME, "")
OWN_PATCH = "@@ -1,9 +1,10 @@\n+status: accepted\n-status: proposed\n+  approved-by: owner\n+  approval-ref: %s\n" % TAP
def ocmp(extra=()): return {"files": [{"filename": REC, "patch": OWN_PATCH, "changes": 4}] + [{"filename": n, "patch": p, "changes": 1} for n, p in extra]}
GUARD = ('if not ref or not any(l.get("role") == "owner-tap" and l.get("relay_ref") == ref for l in lines):', 'if False:')
d = fx([REC], roles=ROLES + ["owner-tap"], refs={"owner-tap": TAP}, head_text={REC: own()}, base_text={REC: base}, cmp_head=ocmp())
check("an owner-approved acceptance with a matching owner-tap line is GREEN with no approved-commit passes", run(d), "GREEN")
d = fx([REC], roles=ROLES + ["owner-tap"], refs={"owner-tap": TAP}, head_text={REC: own()}, base_text={REC: base}, cmp_head=ocmp())
check("an owner-approved acceptance prints the NOTE that names the tap ref", subprocess.run([sys.executable, "-I", SRC, FULL, str(PR), H, d], capture_output=True, text=True).stdout, "NOTE: verdict v2\nNOTE: " + REC + " is accepted on the owner's card tap " + TAP)
d = fx([REC], roles=ROLES + ["owner-tap"], refs={"owner-tap": "cmsg_CARDMESSAGE01"}, head_text={REC: own()}, base_text={REC: base}, cmp_head=ocmp())
check("an owner-tap line with another relay ref refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: approved-by owner needs an owner-tap line", mutate(*GUARD), d)
d = fx([REC], roles=ROLES, head_text={REC: own()}, base_text={REC: base}, cmp_head=ocmp())
check("an owner-approved acceptance with no owner-tap line refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: approved-by owner needs an owner-tap line")
d = fx([REC], roles=ROLES + ["owner-tap"], refs={"owner-tap": TAP}, head_text={REC: own("")}, base_text={REC: base}, cmp_head=ocmp())
check("an owner-approved acceptance with an empty approval-ref refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: approved-by owner needs an owner-tap line")
d = fx([REC], roles=ROLES + ["owner-tap"], refs={"owner-tap": TAP}, head_text={REC: own()}, base_text={REC: base}, cmp_head={"files": [{"filename": REC, "patch": OWN_PATCH + "+one more body line\n", "changes": 5}]})
check("an extra changed line in the owner-approved record refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: approved-by owner allows only the acceptance fields", mutate('if e2 or h:', 'if False:'), d)
d = fx([REC, "hosts/x.sh"], roles=ROLES + ["owner-tap"], refs={"owner-tap": TAP}, head_text={REC: own()}, base_text={REC: base}, cmp_head=ocmp(extra=[("hosts/x.sh", "@@\n+rm -rf\n")]))
check("an extra changed file beside an owner-approved record refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: approved-by owner allows only the acceptance fields")
# An owner-approved record that names the commit the owner tapped (approved-commit): the PR's net change must equal that commit's.
OTHER = "docs/runbooks/x.md"
def acmp_(files): return {"files": [{"filename": n, "patch": p, "changes": 1} for n, p in files]}
SPREAD = [(REC, OWN_PATCH), (OTHER, "@@\n+a line the owner's card named\n")]
CMP_MUT = ('if odiff:', 'if False:')
def ownc(name, headcmp, want, ref=TAP, mut=False):
    d = fx([REC, OTHER], roles=ROLES + ["owner-tap"], refs={"owner-tap": TAP}, head_text={REC: own(ref, commit=True)}, base_text={REC: base}, cmp_head=headcmp, approved=acmp_(SPREAD), approved_roles=None)
    check(name, run(d), want, mutate(*CMP_MUT) if mut else None, d if mut else None)
ownc("an owner-approved PR whose net change equals the approved commit's is GREEN", acmp_(SPREAD), "GREEN")
ownc("an owner-approved PR with one extra line outside the front matter is refused", acmp_(SPREAD + [("docs/other.md", "@@\n+extra\n")]), "NOT GREEN: docs/decisions/0099-x.md: the PR's net change differs from the owner-approved commit", mut=True)
ownc("an owner-approved PR that lacks a line of the approved commit is refused", acmp_([(REC, OWN_PATCH)]), "NOT GREEN: docs/decisions/0099-x.md: the PR's net change differs from the owner-approved commit")
ownc("an owner-approved PR with a tap ref that does not match is refused", acmp_(SPREAD), "NOT GREEN: docs/decisions/0099-x.md: approved-by owner needs an owner-tap line", ref="cmsg_CARDMESSAGE01")
d = fx([REC, OTHER], roles=ROLES + ["owner-tap"], refs={"owner-tap": TAP}, head_text={REC: own(commit=True)}, base_text={REC: base}, cmp_head=acmp_(SPREAD), approved=None)
check("an owner-approved PR whose approved-commit compare cannot be read is refused", run(d), "NOT GREEN: docs/decisions/0099-x.md: the compare for approved-commit")
REC2 = "docs/decisions/0098-y.md"
d = fx([REC, REC2], roles=ROLES + ["owner-tap"], refs={"owner-tap": TAP}, head_text={REC: own(), REC2: own().replace("D-0099", "D-0098")}, base_text={REC: base, REC2: base.replace("D-0099", "D-0098")}, cmp_head={"files": [{"filename": REC, "patch": OWN_PATCH, "changes": 4}, {"filename": REC2, "patch": OWN_PATCH, "changes": 4}]})
check("a PR that accepts two owner-approved records is refused (one record per PR)", run(d), "NOT GREEN: docs/decisions/0099-x.md: approved-by owner allows only the acceptance fields")
d = fx([REC], roles=ROLES[1:] + ["owner-tap"], refs={"owner-tap": TAP}, head_text={REC: own()}, base_text={REC: base}, cmp_head=ocmp())
check("an owner-approved acceptance still needs the reviewer's pass on the PR head", run(d), "NOT GREEN: ledger lacks reviewer")
d = fx([REC], roles=ROLES + ["owner-tap"], refs={"owner-tap": TAP}, head_text={REC: own()}, base_text={REC: base}, cmp_head=None)
check("an owner-approved acceptance with no compare refuses", run(d), "NOT GREEN: docs/decisions/0099-x.md: the compare for head could not be read")
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
# A changed record with no readable head content never passes (a failed contents read); a removed record may skip.
d = fx([REC], head_text={}, base_text={REC: base})
check("a changed record whose head content is missing is refused", run(d), "NOT GREEN: docs/decisions/0099-x.md: its content at the head could not be read", mutate('if fstatus.get(n) != "removed" and content("head", n) is None:', 'if False:'), d)
d = fx([REC], removed=[REC], head_text={}, base_text={REC: base})
check("a removed record needs no head content", run(d), "GREEN")
MANY = ["docs/many/f%d.md" % i for i in range(1642)]
d = fx(MANY); check("1642 changed files are checked, not refused", run(d), "GREEN", mutate('len(files) >= 3000', 'len(files) >= 100'), d)
d = fx(MANY + ["docs/many/g%d.md" % i for i in range(1400)]); check("3000 or more changed files are refused", run(d), "NOT GREEN: 3000 or more changed files", mutate('len(files) >= 3000', 'False'), d)
# Unverified commits are named when GitHub says blocked; they never turn a clean merge into a refusal.
def commits(d, rows): json.dump([{"sha": sha, "commit": {"verification": {"verified": ok, "reason": why}}} for sha, ok, why in rows], open(d + "/commits.json", "w"))
BLK = {"mergeable_state": "blocked"}
d = fx(DOC, pr_over=BLK); commits(d, [("d141d16" + "0" * 33, False, "no_user"), ("08af8d8" + "0" * 33, True, "valid")])
check("blocked: the unverified commit is named with its reason", run(d), "NOT GREEN: GitHub does not report a clean merge (mergeable=True, state=blocked); commit d141d16 is not verified (no_user)", mutate('for c in bad[:5]:', 'for c in []:'), d)
d = fx(DOC, pr_over=BLK); commits(d, [("08af8d8" + "0" * 33, True, "valid")])
check("blocked with all commits verified names none", run(d), "NOT GREEN: GitHub does not report a clean merge (mergeable=True, state=blocked)")
check("blocked with all commits verified adds no commit reason", "commit " in run(d) and "is not verified" in run(d), False)
d = fx(DOC, pr_over=BLK)
check("blocked with no commits file still refuses, without a commit reason", "is not verified" in run(d), False)
d = fx(DOC, roles=["reviewer"]); commits(d, [("d141d16" + "0" * 33, False, "unknown_key")])
check("a clean merge stays GREEN even if a commit reads unverified", run(d), "GREEN")
# A newer run of the same Actions job replaces an older one (editing the description runs spec-line again).
def cr(i, name, concl, suite): return {"id": i, "name": name, "status": "completed", "conclusion": concl, "check_suite": {"id": suite}}
def wr(suite, wf, event="pull_request", sha=H): return {"check_suite_id": suite, "workflow_id": wf, "event": event, "head_sha": sha}
def runs(d, wruns, total=None): json.dump({"total_count": len(wruns) if total is None else total, "workflow_runs": wruns}, open(d + "/runs.json", "w"))
OLDNEW = {"total_count": 3, "check_runs": [cr(10, "line", "failure", 1), cr(20, "line", "success", 2), cr(21, "tests", "success", 2)]}
d = fx(DOC, roles=["reviewer"], checks=OLDNEW); runs(d, [wr(1, 77), wr(2, 77)])
check("a failed run replaced by a newer run of the same job is GREEN", run(d), "GREEN", mutate('    gone = superseded(runs, d, head)', '    gone = set()'), d)
d = fx(DOC, roles=["reviewer"], checks=OLDNEW)
check("without runs.json every run counts", run(d), "NOT GREEN: check line: failure")
d = fx(DOC, roles=["reviewer"], checks=OLDNEW); runs(d, [wr(1, 77), wr(2, 78)])
check("a passing job of the same name in another workflow does not hide a failure", run(d), "NOT GREEN: check line: failure", mutate('job = {w["check_suite_id"]: (w["workflow_id"], w["event"])', 'job = {w["check_suite_id"]: (0, w["event"])'), d)
d = fx(DOC, roles=["reviewer"], checks=OLDNEW); runs(d, [wr(1, 77, "push"), wr(2, 77)])
check("a run of another event does not hide a failure", run(d), "NOT GREEN: check line: failure", mutate('job = {w["check_suite_id"]: (w["workflow_id"], w["event"])', 'job = {w["check_suite_id"]: (w["workflow_id"], 0)'), d)
d = fx(DOC, roles=["reviewer"], checks=OLDNEW); runs(d, [wr(1, 77, sha="f" * 40), wr(2, 77)])
check("a workflow run of another head is not used", run(d), "NOT GREEN: check line: failure", mutate('for w in wruns if w.get("head_sha") == head}', 'for w in wruns}'), d)
d = fx(DOC, roles=["reviewer"], checks=OLDNEW); runs(d, [wr(1, 77), wr(2, 77)], total=300)
check("a partial runs.json drops nothing", run(d), "NOT GREEN: check line: failure", mutate('if wr.get("total_count", len(wruns)) != len(wruns): return set()', 'pass'), d)
d = fx(DOC, roles=["reviewer"], checks={"total_count": 2, "check_runs": [cr(10, "line", "success", 1), cr(20, "line", "failure", 2)]}); runs(d, [wr(1, 77), wr(2, 77)])
check("a newer failed run is not hidden by an older pass", run(d), "NOT GREEN: check line: failure", mutate('if k not in newest or r["id"] > newest[k]', 'if k not in newest or r["id"] < newest[k]'), d)
d = fx(DOC, roles=["reviewer"], checks={"total_count": 2, "check_runs": [cr(10, "CodeQL", "failure", 5), cr(20, "CodeQL", "success", 6)]}); runs(d, [])
check("check runs with no workflow run behind them all count", run(d), "NOT GREEN: check CodeQL: failure")
d = fx(DOC, roles=["reviewer"], checks=OLDNEW); open(d + "/runs.json", "w").write("not json")
check("a runs.json that does not parse drops nothing", run(d), "NOT GREEN: check line: failure")
d = tempfile.mkdtemp(dir=tmp)
check("a missing input is a refusal, not a pass", run(d), "NOT GREEN: could not decide")
shutil.rmtree(tmp)
sys.exit(1 if fails else 0)
PY
