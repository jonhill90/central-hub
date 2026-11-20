#!/bin/bash
# agent-browser's argument checks, run with no browser: a bad call exits 2 with the usage line, `status` and `stop` with
# nothing running say so, and the role installs the script and its front wrapper. The browser itself (start, open, shot,
# a sign-in kept across a restart, the timer) was run by hand with Playwright 1.64.1 on 2026-11-20.
set -euo pipefail
cd "$(dirname "$0")/../../.."
script=hosts/ansible/roles/agent_box/files/agent-browser.py
tasks=hosts/ansible/roles/agent_box/tasks/main.yml
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export AGENT_BROWSER_STATE="$t/state"
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }

expect_rc() {  # expect_rc <want> <label> <args...>
  local want=$1 label=$2; shift 2
  set +e; out=$(python3 -I "$script" "$@" 2>&1); rc=$?; set -e
  if [ "$rc" = "$want" ]; then ok "$label (rc $rc)"; else bad "$label: rc $rc, want $want: $out"; fi
}

expect_rc 2 "no arguments"
expect_rc 2 "unknown command" launch
expect_rc 2 "minutes out of range" start --minutes 999
expect_rc 2 "minutes not a number" start --minutes ten
expect_rc 2 "open needs an http(s) address" open file:///etc/passwd
expect_rc 2 "shot needs one path" shot
expect_rc 1 "status with nothing running" status
expect_rc 0 "stop with nothing running" stop
expect_rc 1 "open with nothing running" open https://example.com

grep -q 'src: agent-browser.py' "$tasks" && ok "role copies the script" || bad "role does not copy agent-browser.py"
grep -q 'dest: "{{ agent_box_front_dir }}/agent-browser"' "$tasks" && ok "role puts agent-browser on the path" \
  || bad "role has no agent-browser front wrapper"
grep -q -- '--remote-debugging-address=127.0.0.1' "$script" && ok "DevTools bound to 127.0.0.1" \
  || bad "DevTools is not bound to 127.0.0.1"

echo "$fails failed"
[ "$fails" -eq 0 ]
