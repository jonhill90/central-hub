#!/usr/bin/env bash
# templates/sudoers.j2 gives the session user only a wrapper's session_args, and the runner user its args (D-0041).
#   1. A wrapper with session_args: the session's line has them, the runner's line has the full args.
#   2. A wrapper without session_args: both users get args, as before.
#   3. An empty session_args: the session user gets no line for that wrapper.
#   4. The real wrapper list: tailnet-stack's session line has no card-ID apply (it has apply-recorded), the runner's has it.
#   5-6. pr-merge: sessions get `check *` only; pass-record: add, show, halt, resume; the runner gets neither.
#   7. proxmox-host runs as its own user (run_as hostops): the session's line has check, check <job>, log and guard status, the
#      runner's adds apply, and neither runs it as the keys user. Sessions may also run guard clear.
#   8-9. tailnet-policy: as guardops (D-0063), sessions get plan, the ledger actions, apply-recorded and log, the runner also the
#        card-ID apply; vps-host: status and log only; the runner gets every action (D-0046).
#   11. callers (D-0063 rule 4): guardops may run proxmox-host's guard arm, confirm, rollback and status as hostops, and nothing
#       else; a session may run guard status only.
# Usage: .github/hosts-check/tests/test_sudoers_session_args.sh   (needs python3 with jinja2 and pyyaml)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
fail=0
out=$(python3 - "$root" <<'PY'
import sys, yaml, jinja2
root = sys.argv[1]
role = root + "/hosts/ansible/roles/agent_box/"
env = jinja2.Environment(loader=jinja2.FileSystemLoader(role + "templates"))
env.filters["regex_replace"] = lambda s, a, b: __import__("re").sub(a, b, s)
env.filters["bool"] = bool
t = env.get_template("sudoers.j2")
def render(ws):
    return t.render(agent_box_wrappers=ws, agent_box_user="sess", agent_box_keys_user="keys",
                    agent_box_libexec_dir="/x", agent_box_self_apply=False, agent_box_runner_user="run")
def lines(txt, user):
    return [l for l in txt.splitlines() if l.startswith(user + " ALL=(keys)")]
a = render([{"name": "w", "args": ["plan", "apply *"], "session_args": ["plan"], "runner": True}])
print("1", lines(a, "sess") == ["sess ALL=(keys) NOPASSWD: /x/w.sh plan"], lines(a, "run") == ["run ALL=(keys) NOPASSWD: /x/w.sh plan, /x/w.sh apply *"])
b = render([{"name": "w", "args": ["plan", "log"], "runner": True}])
print("2", lines(b, "sess") == ["sess ALL=(keys) NOPASSWD: /x/w.sh plan, /x/w.sh log"], lines(b, "run") == ["run ALL=(keys) NOPASSWD: /x/w.sh plan, /x/w.sh log"])
c = render([{"name": "w", "args": ["apply *"], "session_args": [], "runner": True}])
print("3", lines(c, "sess") == [], len(lines(c, "run")) == 1)
d = yaml.safe_load(open(role + "defaults/main.yml"))["agent_box_wrappers"]
ts = [w for w in d if w["name"] == "tailnet-stack"][0]
e = render([ts])
print("4", len(lines(e, "sess")) == 1 and " apply *" not in lines(e, "sess")[0] and "apply-recorded *" in lines(e, "sess")[0], "apply *" in lines(e, "run")[0])
pm = [w for w in d if w["name"] == "pr-merge"][0]
pr = [w for w in d if w["name"] == "pass-record"][0]
g = render([pm, pr])
sl = lines(g, "sess")
print("5", "pr-merge.sh check *" in sl[0] and "merge *" not in sl[0] and "sweep" not in sl[0], all(x in sl[1] for x in ("add *", "show *", "halt *", "resume *")))
print("6", lines(g, "run") == [], not any(w.get("runner") for w in (pm, pr)))
ph = [w for w in d if w["name"] == "proxmox-host"][0]
h = render([ph]).splitlines()
hs = [l for l in h if l.startswith("sess ALL=")]
hr = [l for l in h if l.startswith("run ALL=")]
ses7 = "sess ALL=(hostops) NOPASSWD: " + ", ".join("/x/proxmox-host.sh " + x for x in ["check", "check *", "apply-recorded *", "pass *", "go *", "ledger", "ledger *", "log", "guard status", "guard clear"])
run7 = "run ALL=(hostops) NOPASSWD: " + ", ".join("/x/proxmox-host.sh " + x for x in ["check", "check *", "apply *", "apply-recorded *", "pass *", "go *", "ledger", "ledger *", "log"])
# The session line has no three-argument `apply`: that form takes a pass ID the box cannot check, so only the runner has it.
print("7", hs == [ses7] and " apply *" not in hs[0], hr == [run7])
tp = render([w for w in d if w["name"] == "tailnet-policy"])
tpl = tp.splitlines()
print("8", [l for l in tpl if l.startswith("sess ALL=")] == ["sess ALL=(guardops) NOPASSWD: /x/tailnet-policy.sh plan, /x/tailnet-policy.sh apply-recorded *, /x/tailnet-policy.sh pass *, /x/tailnet-policy.sh go *, /x/tailnet-policy.sh ledger, /x/tailnet-policy.sh log"],
      [l for l in tpl if l.startswith("run ALL=")] == ["run ALL=(guardops) NOPASSWD: /x/tailnet-policy.sh plan, /x/tailnet-policy.sh apply *, /x/tailnet-policy.sh apply-recorded *, /x/tailnet-policy.sh pass *, /x/tailnet-policy.sh go *, /x/tailnet-policy.sh ledger, /x/tailnet-policy.sh log"])
vh = render([w for w in d if w["name"] == "vps-host"])
print("9", lines(vh, "sess") == ["sess ALL=(keys) NOPASSWD: /x/vps-host.sh status, /x/vps-host.sh log"],
      lines(vh, "run") == ["run ALL=(keys) NOPASSWD: /x/vps-host.sh bootstrap, /x/vps-host.sh apply, /x/vps-host.sh secrets, /x/vps-host.sh secrets rotate, /x/vps-host.sh status, /x/vps-host.sh log"])
oc = render([w for w in d if w["name"] == "opnsense-cert-check"])
print("10", lines(oc, "sess") == ["sess ALL=(keys) NOPASSWD: /x/opnsense-cert-check.sh check, /x/opnsense-cert-check.sh status"], lines(oc, "run") == [])
gl = [l for l in h if l.startswith("guardops ")]
print("11", gl == ["guardops ALL=(hostops) NOPASSWD: " + ", ".join("/x/proxmox-host.sh guard " + x for x in ["arm", "confirm", "rollback", "status"])],
      "Defaults:guardops env_reset" in h and not any("guard " in l for l in hr))
lt = [w for w in d if w["name"] == "lab-token"][0]
lp = [w for w in d if w["name"] == "lab-token-put"][0]
ltt = render([lt, lp])
print("12", [l for l in ltt.splitlines() if l.startswith("sess ")] == ["sess ALL=(hostops) NOPASSWD: /x/lab-token.sh status, /x/lab-token.sh mint *"],
      [l for l in ltt.splitlines() if l.startswith("hostops ")] == ["hostops ALL=(keys) NOPASSWD: /x/lab-token-put.sh exists, /x/lab-token-put.sh put"])
sp = [w for w in d if w["name"] == "secrets-store-prod"][0]
spl = lines(render([sp]), "sess")
forms = ["/x/secrets-store-prod.sh owner-login " + x for x in ("owner", "test", "check-test", "remove-test")]
print("13", len(spl) == 1 and all(f in spl[0].split(", ") or spl[0].endswith(": " + f) or (", " + f) in spl[0] for f in forms) and "owner-login *" not in spl[0],
      "owner-login *" not in render([sp]))
PY
)
check() { # number, text
  if grep -q "^$1 True True" <<< "$out"; then echo "ok   $2"; else echo "FAIL $2"; fail=1; fi
}
check 1 "1. session_args for the session, full args for the runner"
check 2 "2. no session_args: both get args"
check 3 "3. empty session_args: the session gets no line"
check 4 "4. tailnet-stack: no card-ID apply in the session's line (apply-recorded yes), apply in the runner's"
check 5 "5. sessions: pr-merge check only (no merge, no sweep); pass-record add, show, halt, resume"
check 6 "6. the runner user gets no pr-merge or pass-record line (the merge job is gone)"
check 7 "7. proxmox-host: as hostops; the session checks and reads the log, only the runner has the ungated apply; sessions have apply-recorded"
check 8 "8. tailnet-policy: as guardops, the session gets plan, the ledger and apply-recorded, the runner also the card-ID apply"
check 9 "9. vps-host: the session gets status and log only, the runner every action"
check 10 "10. opnsense-cert-check: the session gets check and status as the keys user, the runner nothing"
check 11 "11. guardops: only proxmox-host guard arm, confirm, rollback and status as hostops; the runner gets no guard"
check 12 "12. lab-token: the session may status and mint as hostops; only hostops may run lab-token-put (as keys); the session has no line for it"
check 13 "13. secrets-store-prod: the four exact owner-login forms are in the sudoers line, no owner-login *"
exit "$fail"
