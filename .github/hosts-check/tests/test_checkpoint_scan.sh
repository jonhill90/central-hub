#!/usr/bin/env bash
# The box's checkpoint scan (hosts/ansible/roles/agent_box/files/checkpoint-scan.py and .sh), with GitHub and the wake
# stubbed in-process and a throwaway App key, so no GitHub account is needed:
#   1. The token is asked for with the two repositories and Contents and Pull requests read only, and revoked.
#   2. said-i-would: an Open row whose line last changed over 2 hours ago is a finding; a younger Open row, an old
#      Done row and an old Standing row are not.
#   3. Merges: a merge within 2 hours whose head has no reviewer pass is a finding; one with the pass, and an old one
#      without, are not.
#   4. Ledger times: a relay time later than the box's own time, or over a day before it, is a finding; a normal one
#      is not.
#   5. Moved heads: an open pull request whose pass is on an earlier head is a finding; one with no pass at all, and
#      one whose current head has the pass, are not.
#   6. A clean scan prints "no findings", exits 0 and posts nothing.
#   7. Findings exit 3 and post the count of new ones; a finding seen in the last run posts nothing, and neither does
#      one dropping out; a clean scan clears the memory, so a recurrence posts again; a failed post is tried again
#      next run. `show` prints the last report.
#   8. A GitHub read that fails is itself a finding, and is posted.
#  10. The same stale said-i-would row, scanned at three times, reads the same and posts once (no age in the text).
#  11. A crash of the scan (any other exception) is a finding, named by its type only, and is posted.
#   9. The wrapper passes run and show only; the sudo line passes run and show only; the role installs the script, the
#      service with SuccessExitStatus=3, and the timer.
# Usage: .github/hosts-check/tests/test_checkpoint_scan.sh   (needs python3, openssl, PyYAML)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
role=$root/hosts/ansible/roles/agent_box
files=$role/files
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

openssl genrsa -out "$t/github-app.pem" 2048 2>/dev/null

cat > "$t/harness.py" <<'PY'
import datetime, importlib.util, io, json, os, sys, contextlib
src, tmp, case = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("scan", src)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.KEYS, m.WORK = tmp, os.path.join(tmp, "work")
T = datetime.datetime(2026, 11, 19, 12, 0, 0, tzinfo=datetime.timezone.utc)
m.now = lambda: T
def ago(**kw): return (T - datetime.timedelta(**kw)).strftime("%Y-%m-%dT%H:%M:%SZ")
H = lambda c: c * 40

SAID = "\n".join([
    "# What the orchestrator said it would do", "",
    "| Said (UTC) | What | State | Proof |", "|---|---|---|---|",
    "| 11-19 01:00 | old open thing | Open | none |",          # line 5: blamed 3h ago -> finding
    "| 11-19 10:30 | young open thing | Open | none |",        # line 6: blamed 1h ago
    "| 11-19 01:00 | old done thing | Done | proof |",         # line 7: blamed 3h ago
    "| 11-19 01:00 | old standing thing | Standing | memory |", # line 8: blamed 3h ago
    "", "After the table | Open | not a row |"])
FIX = {
  "blame": {"repository": {"defaultBranchRef": {"target": {"oid": "x", "file": {"object": {"text": SAID}}, "blame": {"ranges": [
      {"startingLine": 1, "endingLine": 5, "commit": {"committedDate": ago(hours=3)}},
      {"startingLine": 6, "endingLine": 6, "commit": {"committedDate": ago(hours=1)}},
      {"startingLine": 7, "endingLine": 10, "commit": {"committedDate": ago(hours=3)}}]}}}}},
  "closed:central-hub": [
      {"number": 10, "merged_at": ago(hours=1), "head": {"sha": H("a")}},   # passed
      {"number": 11, "merged_at": ago(hours=1), "head": {"sha": H("b")}},   # no pass -> finding
      {"number": 12, "merged_at": ago(hours=3), "head": {"sha": H("c")}},   # old
      {"number": 13, "merged_at": None, "head": {"sha": H("d")}}],          # closed unmerged
  "closed:agent-notebook": [],
  "open:central-hub": [
      {"number": 20, "head": {"sha": H("e")}},   # pass on earlier head 1 -> finding
      {"number": 21, "head": {"sha": H("f")}},   # no pass anywhere
      {"number": 22, "head": {"sha": H("9")}}],  # pass on this head
  "open:agent-notebook": [],
}
def ledger_line(pr, head, relay, box, role="reviewer", repo="central-hub"):
    return {"role": role, "repo": "jonhill90/" + repo, "pr": pr, "head": head, "relay_ref": "cmsg_" + "x" * 20,
            "relay_time": relay, "recorder": "orchestrator", "box_time": box}
def write_ledger(lines):
    d = os.path.join(m.WORK, "passes", "central-hub"); os.makedirs(d, exist_ok=True)
    for o in lines:
        with open(os.path.join(d, o["head"] + ".jsonl"), "a") as f: f.write(json.dumps(o) + "\n")
LEDGER = [ledger_line(10, H("a"), ago(hours=1, minutes=1), ago(hours=1)),
          ledger_line(20, H("1"), ago(hours=5), ago(hours=5)),
          ledger_line(22, H("9"), ago(minutes=30), ago(minutes=29)),
          ledger_line(30, H("2"), ago(minutes=10), ago(minutes=20)),         # relay after the box -> finding
          ledger_line(31, H("3"), ago(days=2), ago(minutes=20)),             # over a day before -> finding
          ledger_line(32, H("4"), ago(days=2), ago(days=2, minutes=-1))]     # old line, outside the window

class FakeGH:
    calls = []
    fail = None
    def __init__(self): pass
    def get(self, path):
        FakeGH.calls.append(path)
        if FakeGH.fail and FakeGH.fail in path: raise m.ScanError("GitHub returned 502 for " + path.split("?")[0])
        repo = path.split("/")[3]
        kind = "open" if "state=open" in path else "closed"
        return FIX["%s:%s" % (kind, repo)]
    def graphql(self, q, v):
        assert v == {"o": "jonhill90", "n": "agent-notebook", "p": "00-inbox/00d-dashboards/said-i-would.md"}, v
        return FIX["blame"]
    def close(self): FakeGH.calls.append("close")
posts = []
m.post = lambda n: posts.append(n) or 0

def run():
    out = io.StringIO()
    with contextlib.redirect_stdout(out): rc = m.run()
    return rc, out.getvalue()

if case == "token":
    seen = []
    def http(method, url, bearer, body=None):
        seen.append((method, url, bearer, body))
        if url.endswith("/installation") and method == "GET": return 200, {"id": 42}
        if url.endswith("/access_tokens"): return 201, {"token": "ghs_SECRETTOKEN"}
        return 204, None
    m.http = http
    os.makedirs(m.WORK, exist_ok=True)
    json.dump({"github_app_id": 1}, open(os.path.join(m.WORK, "ci-runner.json"), "w"))
    g = m.GitHub(); g.close()
    tok = [s for s in seen if s[1].endswith("/access_tokens")][0]
    jwt_ok = seen[0][2].count(".") == 2 and seen[0][2] != "ghs_SECRETTOKEN"
    print(json.dumps({"body": tok[3], "revoke": seen[-1][:3], "jwt_ok": jwt_ok}))
    sys.exit(0)

m.GitHub = FakeGH
if case == "checks":
    write_ledger(LEDGER)
    rc, out = run()
    print(json.dumps({"rc": rc, "out": out, "posts": posts}))
elif case == "clean":
    FIX["blame"]["repository"]["defaultBranchRef"]["target"]["blame"]["ranges"][0]["commit"]["committedDate"] = ago(minutes=5)
    FIX["closed:central-hub"] = FIX["closed:central-hub"][:1]
    FIX["open:central-hub"] = FIX["open:central-hub"][1:]
    write_ledger(LEDGER[:1] + LEDGER[2:3])
    rc, out = run()
    print(json.dumps({"rc": rc, "out": out, "posts": posts}))
elif case == "dedupe":
    write_ledger(LEDGER)
    r1 = run(); r2 = run()
    FIX["open:central-hub"] = FIX["open:central-hub"][1:]          # one finding fewer: a changed report
    r3 = run()
    FIX["closed:central-hub"] = []; FIX["open:central-hub"] = []
    FIX["blame"]["repository"]["defaultBranchRef"]["target"]["blame"]["ranges"][0]["commit"]["committedDate"] = ago(minutes=5)
    import shutil; shutil.rmtree(os.path.join(m.WORK, "passes"))
    r4 = run()                                                    # clean: memory cleared
    FIX["closed:central-hub"] = [{"number": 11, "merged_at": ago(hours=1), "head": {"sha": H("b")}}]
    r5 = run(); r6 = run()
    FIX["closed:central-hub"].append({"number": 14, "merged_at": ago(hours=1), "head": {"sha": H("5")}})
    m.post = lambda n: posts.append(-n) or 1                     # checkpoint-note fails once
    r7 = run()
    m.post = lambda n: posts.append(n) or 0
    r8 = run(); r9 = run()
    out = io.StringIO()
    with contextlib.redirect_stdout(out): m.show()
    print(json.dumps({"rcs": [r[0] for r in (r1, r2, r3, r4, r5, r6, r7, r8, r9)], "posts": posts, "show": out.getvalue(),
                      "wakes": [r[1].strip().splitlines()[-1] for r in (r1, r2, r3, r5, r6, r7, r8, r9)]}))
elif case == "aging":
    FIX["closed:central-hub"] = FIX["closed:central-hub"][:1]
    FIX["open:central-hub"] = FIX["open:central-hub"][1:]
    write_ledger(LEDGER[:1] + LEDGER[2:3])
    r1 = run()
    T = T + datetime.timedelta(minutes=30); m.now = lambda: T
    r2 = run()
    T = T + datetime.timedelta(minutes=30); m.now = lambda: T     # line 6 (blamed 11:00) is then exactly 2h old, not over
    r3 = run()
    print(json.dumps({"rcs": [r1[0], r2[0], r3[0]], "posts": posts, "outs": [r1[1], r2[1], r3[1]]}))
elif case == "crash":
    def boom(self, path): raise KeyError("id")
    FakeGH.get = boom
    r1 = run(); r2 = run()
    print(json.dumps({"rcs": [r1[0], r2[0]], "posts": posts, "out": r1[1]}))
elif case == "error":
    FakeGH.fail = "state=open"
    FIX["blame"]["repository"]["defaultBranchRef"]["target"]["blame"]["ranges"][0]["commit"]["committedDate"] = ago(minutes=5)
    FIX["closed:central-hub"] = FIX["closed:central-hub"][:1]
    write_ledger(LEDGER[:1])
    rc, out = run()
    print(json.dumps({"rc": rc, "out": out, "posts": posts}))
PY

h() { rm -rf "$t/work"; python3 -I "$t/harness.py" "$files/checkpoint-scan.py" "$t" "$1"; }

# 1
r=$(h token)
if python3 -I -c 'import json,sys; d=json.loads(sys.argv[1])
assert d["body"] == {"repositories": ["central-hub", "agent-notebook"], "permissions": {"contents": "read", "pull_requests": "read"}}, d["body"]
assert d["revoke"] == ["DELETE", "https://api.github.com/installation/token", "ghs_SECRETTOKEN"], d["revoke"]
assert d["jwt_ok"]' "$r" 2>"$t/err"; then
  ok "1. token for central-hub and agent-notebook with Contents and Pull requests read only, signed JWT, revoked"
else bad "1. $(cat "$t/err") [$r]"; fi

r=$(h checks)
chk() { python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); exec(sys.argv[2])' "$r" "$1" 2>"$t/err"; }
# 2
if chk 'o=d["out"]
assert "said-i-would: line 5 (said 11-19 01:00) is Open, unchanged since 2026-11-19T09:00:00Z\n" in o, o
assert "line 6" not in o and "line 7" not in o and "line 8" not in o and "line 10" not in o, o'; then
  ok "2. said-i-would: only the Open row unchanged for over 2 hours is a finding"
else bad "2. $(cat "$t/err")"; fi
# 3
if chk 'o=d["out"]
assert "unpassed merge: central-hub#11 merged 2026-11-19T11:00:00Z at head bbbbbbb with no reviewer pass in the ledger" in o, o
assert "#10 merged" not in o and "#12 merged" not in o and "#13" not in o, o'; then
  ok "3. merges: only the recent merge with no reviewer pass is a finding"
else bad "3. $(cat "$t/err")"; fi
# 4
if chk 'o=d["out"]
assert "ledger time: central-hub#30 head 2222222" in o and "is later than the box recorded it" in o, o
assert "ledger time: central-hub#31 head 3333333" in o and "more than a day before" in o, o
assert "#32" not in o and "ledger time: central-hub#10" not in o and "ledger time: central-hub#22" not in o, o'; then
  ok "4. ledger times: a relay after the box's time or over a day before is a finding; normal and old lines are not"
else bad "4. $(cat "$t/err")"; fi
# 5
if chk 'o=d["out"]
assert "moved head: central-hub#20 head eeeeeee has no reviewer pass; the pass is on 1111111" in o, o
assert "#21" not in o and "#22 head" not in o, o
assert d["rc"] == 3 and d["posts"] == [5], (d["rc"], d["posts"])'; then
  ok "5. moved heads: only the open PR whose pass is on an earlier head; 5 findings, exit 3, one post of 5"
else bad "5. $(cat "$t/err")"; fi

# 6
r=$(h clean)
if chk 'assert d["rc"] == 0 and d["posts"] == [] and d["out"].startswith("checkpoint-scan: no findings at 2026-11-19T12:00:00Z"), d'; then
  ok "6. a clean scan prints no findings, exits 0 and posts nothing"
else bad "6. $(cat "$t/err")"; fi

# 7
r=$(h dedupe)
if chk 'assert d["rcs"] == [3, 3, 3, 0, 3, 3, 3, 3, 3], d["rcs"]
assert d["posts"] == [5, 1, -1, 1], d["posts"]
w=d["wakes"]
assert w[0].endswith("wake: posted 5 new") and w[1].endswith("wake: no new finding; not posted"), w
assert w[2].endswith("wake: no new finding; not posted"), w
assert w[3].endswith("wake: posted 1 new") and w[4].endswith("wake: no new finding; not posted"), w
assert "checkpoint-note failed (rc 1)" in w[5] and w[6].endswith("wake: posted 1 new") and w[7].endswith("not posted"), w
assert d["show"].startswith("checkpoint-scan: last scan at 2026-11-19T12:00:00Z, 2 finding(s)") and "unpassed merge: central-hub#14" in d["show"], d["show"]'; then
  ok "7. posts only new findings (5; none for the same or a dropped one; 1 for a recurrence); a failed post is retried; show prints it"
else bad "7. $(cat "$t/err")"; fi

# 8
r=$(h error)
if chk 'o=d["out"]
assert "scan error: central-hub open pull requests: GitHub returned 502 for /repos/jonhill90/central-hub/pulls" in o, o
assert d["rc"] == 3 and d["posts"] == [2], (d["rc"], d["posts"])'; then
  ok "8. a failed GitHub read is a finding of its own, and is posted"
else bad "8. $(cat "$t/err")"; fi

# 10
r=$(h aging)
if chk 'assert d["rcs"] == [3, 3, 3] and d["posts"] == [1], (d["rcs"], d["posts"])
assert all("said-i-would: line 5 (said 11-19 01:00) is Open, unchanged since 2026-11-19T09:00:00Z" in o for o in d["outs"]), d["outs"]
assert "wake: no new finding" in d["outs"][1] and "wake: no new finding" in d["outs"][2], d["outs"]'; then
  ok "10. the same stale row scanned at 12:00, 12:30 and 13:00 reads the same and posts once"
else bad "10. $(cat "$t/err")"; fi

# 11
r=$(h crash)
if chk 'assert d["rcs"] == [3, 3] and d["posts"] == [1], (d["rcs"], d["posts"])
assert "new: scan crashed: KeyError" in d["out"] and "id" not in d["out"].split("KeyError")[1].split("\n")[0], d["out"]'; then
  ok "11. a crash is a finding named by its type only, posted once"
else bad "11. $(cat "$t/err")"; fi

# 9
w1=$(bash "$files/checkpoint-scan.sh" sweep 2>&1; echo "rc=$?")
w2=$(bash "$files/checkpoint-scan.sh" run extra 2>&1; echo "rc=$?")
sudo=$(python3 -I -c 'import sys, yaml
for w in yaml.safe_load(open(sys.argv[1]))["agent_box_wrappers"]:
    if w["name"] == "checkpoint-scan": print(w.get("args"))' "$role/defaults/main.yml" 2>&1)
tasks=$(cat "$role/tasks/main.yml")
svc=$(cat "$role/templates/checkpoint-scan.service.j2")
if [[ $w1 == *"usage: checkpoint-scan run | show"*"rc=2" && $w2 == *"rc=2" && $sudo == "['run', 'show']" &&
      $tasks == *'dest: "{{ agent_box_libexec_dir }}/checkpoint-scan.py"'* && $tasks == *"name: checkpoint-scan.timer"* &&
      $svc == *"ExecStart={{ agent_box_libexec_dir }}/checkpoint-scan.sh run"* && $svc == *"SuccessExitStatus=3"* &&
      $svc == *"User={{ agent_box_keys_user }}"* ]]; then
  ok "9. the wrapper and the sudo line pass run and show only; the role installs the script, the service (exit 3 ok) and the timer"
else bad "9. [$w1] [$w2] [$sudo]"; fi

exit $fail
