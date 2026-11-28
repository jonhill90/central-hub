#!/usr/bin/env bash
# The hub dispatcher's wake (hosts/ansible/roles/agent_box/files/hub-fire.py), with the API call stubbed in-process,
# so no trigger or token is needed:
#   1. Two rings for one project 30 seconds apart make one call; a restart (a fresh process on the same rows) in
#      between still makes one.
#   2. An unanswered ring is tried again after 30 and then 60 minutes, at most 3 calls, then reported unanswered once
#      (exit 4), and nothing more is fired.
#   3. The attempt is written as reserved before the call: a crash during the call leaves a reserved row that counts
#      as sent, so the next ring waits instead of calling again.
#   4. ack answers the ring; a ring after it is a new ring and calls at once. A timeout or an HTTP error uses a try.
#   5. Mode off does nothing and writes nothing; dry-run prints, calls nothing and writes nothing; no token in mode on
#      makes no attempt; a label that is not TASK-NNNN, a project not in the settings or bad settings is refused.
#   6. The call carries no text by default, and only the label when the project sets text; the token is a header only
#      and is never printed; the URL is the trigger's /fire on api.anthropic.com with the routine beta header.
#   7. The role installs hub-fire.py, writes hub-fire.json with mode off by default, and pickup-scan calls ring and ack.
# Usage: .github/hosts-check/tests/test_hub_fire.sh   (needs python3)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
role=$root/hosts/ansible/roles/agent_box
src=$role/files/hub-fire.py
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

python3 -I - "$src" "$t" <<'PY'
import contextlib, datetime, importlib.util, io, json, os, sqlite3, sys

src, tmp = sys.argv[1:3]
sys.dont_write_bytecode = True
fail = []
T0 = datetime.datetime(2026, 11, 28, 12, 0, 0, tzinfo=datetime.timezone.utc)
TOKEN = "sk-ant-oat01-" + "x" * 40


def load(case, mode="on", text=False, tok=True, clock=None, calls=None, result=("sent", 200, "session_01ABC")):
    spec = importlib.util.spec_from_file_location("hubfire", src)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.WORK, m.KEYS = os.path.join(tmp, case, "work"), os.path.join(tmp, case, "keys")
    os.makedirs(m.WORK, exist_ok=True)
    os.makedirs(os.path.join(m.KEYS, "hub-fire"), exist_ok=True)
    cfg = {"trigger": "trig_01ABCDEFGHJKLMNOP"}
    if text:
        cfg["text"] = True
    json.dump({"mode": mode, "projects": {"agent-notebook": cfg}}, open(os.path.join(m.WORK, "hub-fire.json"), "w"))
    tf = os.path.join(m.KEYS, "hub-fire", "agent-notebook.token")
    if tok:
        open(tf, "w").write(TOKEN + "\n")
    elif os.path.exists(tf):
        os.remove(tf)
    clock = clock if clock is not None else [T0]
    m.now = lambda: clock[0]
    calls = calls if calls is not None else []
    real_call = m.call

    def stub(trigger, token, body):
        calls.append((trigger, token, body))
        if result == "crash":
            raise KeyboardInterrupt
        return result
    m.call = stub
    m._real_call = real_call
    return m, clock, calls


def run(m, *argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
        rc = m.main(list(argv))
    return rc, out.getvalue()


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        fail.append(what)


def mins(c, n):
    c[0] = c[0] + datetime.timedelta(minutes=n)


# 1. coalescing, and a restart in between
m, clock, calls = load("c1")
r1 = run(m, "ring", "agent-notebook", "TASK-0401")
clock[0] += datetime.timedelta(seconds=30)
r2 = run(m, "ring", "agent-notebook", "TASK-0401")
check(len(calls) == 1 and r1[0] == 3 and r2[0] == 0, "1: two rings 30 s apart make one call")
m2, _, calls2 = load("c1", clock=clock, calls=calls)
r3 = run(m2, "ring", "agent-notebook", "TASK-0401")
check(len(calls) == 1 and r3[0] == 0, "1: a fresh process on the same rows still makes no second call")

# 2. retries with growing gaps, then unanswered once
m, clock, calls = load("c2")
run(m, "ring", "agent-notebook", "TASK-0401")
mins(clock, 29); run(m, "ring", "agent-notebook", "TASK-0401")
check(len(calls) == 1, "2: no second call before 30 minutes")
mins(clock, 1); run(m, "ring", "agent-notebook", "TASK-0401")
check(len(calls) == 2, "2: second call at 30 minutes")
mins(clock, 59); run(m, "ring", "agent-notebook", "TASK-0401")
check(len(calls) == 2, "2: no third call before 60 minutes more")
mins(clock, 1); run(m, "ring", "agent-notebook", "TASK-0401")
check(len(calls) == 3, "2: third call at 60 minutes more")
mins(clock, 119); rc, out = run(m, "ring", "agent-notebook", "TASK-0401")
check(len(calls) == 3 and rc == 0, "2: nothing before the last gap of 120 minutes")
mins(clock, 1); rc, out = run(m, "ring", "agent-notebook", "TASK-0401")
check(rc == 4 and "unanswered" in out and len(calls) == 3, "2: unanswered reported after 3 calls and the last gap")
mins(clock, 600); rc, out = run(m, "ring", "agent-notebook", "TASK-0401")
check(rc == 0 and len(calls) == 3 and "already reported" in out, "2: unanswered is reported once and nothing more fires")

# 3. reserved before the call; a crash counts as sent
m, clock, calls = load("c3", result="crash")
try:
    run(m, "ring", "agent-notebook", "TASK-0401")
except KeyboardInterrupt:
    pass
rows = sqlite3.connect(os.path.join(m.WORK, "state", "hub-wakes.sqlite")).execute("SELECT state FROM attempts").fetchall()
check(rows == [("reserved",)], "3: the attempt was written as reserved before the call")
m, _, calls = load("c3", clock=clock)
mins(clock, 5); rc, _ = run(m, "ring", "agent-notebook", "TASK-0401")
check(calls == [] and rc == 0, "3: after the crash the reserved attempt counts as sent; the next ring waits")

# 4. ack, a new ring, and tries used by errors
m, clock, calls = load("c4")
run(m, "ring", "agent-notebook", "TASK-0401")
rc, out = run(m, "ack", "agent-notebook")
check("answered" in out, "4: ack answers the open ring")
mins(clock, 1); run(m, "ring", "agent-notebook", "TASK-0401")
check(len(calls) == 2, "4: a ring after ack is a new ring and calls at once")
for res, name in ((("timeout", None, ""), "timeout"), (("refused", 401, ""), "refused 401")):
    m, clock, calls = load("c4-" + name.split()[0], result=res)
    run(m, "ring", "agent-notebook", "TASK-0401")
    mins(clock, 5); run(m, "ring", "agent-notebook", "TASK-0401")
    st = sqlite3.connect(os.path.join(m.WORK, "state", "hub-wakes.sqlite")).execute("SELECT state, code FROM attempts").fetchall()
    check(len(calls) == 1 and st[0][0] == name.split()[0], "4: a %s uses a try and is recorded" % name)

# 5. off, dry-run, no token, refusals
m, clock, calls = load("c5-off", mode="off")
rc, out = run(m, "ring", "agent-notebook", "TASK-0401")
check(calls == [] and not os.path.exists(os.path.join(m.WORK, "state", "hub-wakes.sqlite")) and "off" in out, "5: mode off does nothing and writes nothing")
m, clock, calls = load("c5-dry", mode="dry-run")
rc, out = run(m, "ring", "agent-notebook", "TASK-0401")
rows = sqlite3.connect(os.path.join(m.WORK, "state", "hub-wakes.sqlite")).execute("SELECT count(*) FROM attempts").fetchone()[0]
check(calls == [] and rc == 3 and rows == 0 and "would fire" in out, "5: dry-run prints, calls nothing, writes no attempt")
m, clock, calls = load("c5-flag")
rc, out = run(m, "ring", "agent-notebook", "TASK-0401", "--dry-run")
check(calls == [] and rc == 3, "5: --dry-run in mode on calls nothing")
m, clock, calls = load("c5-tok", tok=False)
rc, out = run(m, "ring", "agent-notebook", "TASK-0401")
rows = sqlite3.connect(os.path.join(m.WORK, "state", "hub-wakes.sqlite")).execute("SELECT count(*) FROM attempts").fetchone()[0]
check(calls == [] and rows == 0 and "no token" in out, "5: no token makes no attempt")
m, clock, calls = load("c5-bad")
check(run(m, "ring", "agent-notebook", "TASK-401; rm")[0] == 2 and calls == [], "5: a label that is not TASK-NNNN is refused")
rc, out = run(m, "ring", "other-project", "TASK-0401")
check(calls == [] and "no trigger" in out, "5: a project not in the settings fires nothing")
json.dump({"mode": "on", "projects": {"agent-notebook": {"trigger": "https://evil.example/x"}}}, open(os.path.join(m.WORK, "hub-fire.json"), "w"))
check(run(m, "ring", "agent-notebook", "TASK-0401")[0] == 2 and calls == [], "5: a trigger that is not trig_... is refused")

# 6. the call itself
m, clock, calls = load("c6")
_, out = run(m, "ring", "agent-notebook", "TASK-0401")
check(calls[0][2] == {}, "6: no text by default")
check(TOKEN not in out, "6: the token is not printed")
m, clock, calls = load("c6-text", text=True)
run(m, "ring", "agent-notebook", "TASK-0401")
check(calls[0][2] == {"text": "TASK-0401"}, "6: with text set, only the label is sent")
seen = {}
class Resp:
    status = 200
    def read(self): return b'{"type":"routine_fire","claude_code_session_id":"session_01XYZ"}'
    def __enter__(self): return self
    def __exit__(self, *a): return False
def fake(req, timeout):
    seen["url"], seen["h"], seen["data"] = req.full_url, dict(req.header_items()), req.data
    return Resp()
m._real_call.__globals__["urllib"].request.urlopen = fake
state = m._real_call("trig_01ABCDEFGHJKLMNOP", TOKEN, {})
check(seen["url"] == "https://api.anthropic.com/v1/claude_code/routines/trig_01ABCDEFGHJKLMNOP/fire", "6: the URL is the trigger's /fire")
check(seen["h"].get("Authorization") == "Bearer " + TOKEN and seen["h"].get("Anthropic-beta") == "experimental-cc-routine-2026-04-01", "6: the token and beta header are headers")
check(state == ("sent", 200, "session_01XYZ"), "6: the session id is kept")

sys.exit(1 if fail else 0)
PY
rc=$?

# 7. the role wiring
grep -q "src: hub-fire.py" "$role/tasks/main.yml" && echo "ok   7: the role installs hub-fire.py" || { echo "FAIL 7: the role installs hub-fire.py"; rc=1; }
grep -q "hub-fire.json" "$role/tasks/main.yml" && echo "ok   7: the role writes hub-fire.json" || { echo "FAIL 7: the role writes hub-fire.json"; rc=1; }
grep -q "^agent_box_hub_fire_mode: \"off\"" "$role/defaults/main.yml" && echo "ok   7: mode is off by default" || { echo "FAIL 7: mode is off by default"; rc=1; }
grep -q '"ring"' "$role/files/pickup-scan.py" && grep -q '"ack"' "$role/files/pickup-scan.py" && echo "ok   7: pickup-scan calls ring and ack" || { echo "FAIL 7: pickup-scan calls ring and ack"; rc=1; }
exit $rc
