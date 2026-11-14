#!/usr/bin/env bash
# templates/sudoers.j2 gives the session user only a wrapper's session_args, and the runner user its args (D-0041).
#   1. A wrapper with session_args: the session's line has them, the runner's line has the full args.
#   2. A wrapper without session_args: both users get args, as before.
#   3. An empty session_args: the session user gets no line for that wrapper.
#   4. The real wrapper list: tailnet-stack's session line has no apply, the runner's has it.
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
print("4", len(lines(e, "sess")) == 1 and "apply" not in lines(e, "sess")[0], "apply *" in lines(e, "run")[0])
PY
)
check() { # number, text
  if grep -q "^$1 True True" <<< "$out"; then echo "ok   $2"; else echo "FAIL $2"; fail=1; fi
}
check 1 "1. session_args for the session, full args for the runner"
check 2 "2. no session_args: both get args"
check 3 "3. empty session_args: the session gets no line"
check 4 "4. tailnet-stack: no apply in the session's line, apply in the runner's"
exit "$fail"
