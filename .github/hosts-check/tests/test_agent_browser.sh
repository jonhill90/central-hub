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

# A port held by someone else: start refuses it, and open refuses to talk to it. A fake /proc/net/tcp names the
# listener's uid (65534, not this user), so this part needs no second user and no root.
printf '%s\n' '  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode' \
  '   0: 0100007F:2406 00000000:0000 0A 00000000:00000000 00:00000000 00000000 65534        0 1 1 0000000000000000 100 0 0 10 0' \
  > "$t/tcp-other"
AGENT_BROWSER_PROC_TCP="$t/tcp-other" expect_rc 1 "start refuses a port another uid listens on" start
grep -q "already taken" <<<"$(AGENT_BROWSER_PROC_TCP="$t/tcp-other" python3 -I "$script" start 2>&1)" \
  && ok "start says the port is taken" || bad "start did not say the port is taken"
mkdir -p "$t/state"; printf '{"chromium_pid": %s, "cdp": "http://127.0.0.1:9222", "stop_at": 0}' "$$" > "$t/state/state.json"
AGENT_BROWSER_PROC_TCP="$t/tcp-other" expect_rc 1 "open refuses a port held by another uid" open https://example.com
rm -f "$t/state/state.json"

grep -q 'src: agent-browser.py' "$tasks" && ok "role copies the script" || bad "role does not copy agent-browser.py"
grep -q 'dest: "{{ agent_box_front_dir }}/agent-browser"' "$tasks" && ok "role puts agent-browser on the path" \
  || bad "role has no agent-browser front wrapper"
grep -q -- '--remote-debugging-address=127.0.0.1' "$script" && ok "DevTools bound to 127.0.0.1" \
  || bad "DevTools is not bound to 127.0.0.1"

# The DevTools port filter: rendered from the role's template with a test user, the session user connects and
# another user is reset. Without the filter the other user connects, which the last step shows. The live part needs
# root and nftables (a container without them runs only the render check).
nftt=hosts/ansible/roles/agent_box/templates/agent-browser.nft.j2
sed -e 's/{{ agent_box_browser_cdp_port }}/9222/; s/{{ agent_box_user }}/ab-session/' "$nftt" > "$t/ab.nft"
grep -q 'oifname "lo" tcp dport 9222 meta skuid != "ab-session" reject' "$t/ab.nft" \
  && ok "filter resets other users' connections to the DevTools port" || bad "filter rule missing from $nftt"
grep -q 'src: agent-browser.nft.j2' "$tasks" && grep -q 'agent-browser-nft.service' "$tasks" \
  && ok "role installs the filter and its unit" || bad "role does not install the DevTools port filter"
if [ "$(id -u)" = 0 ] && command -v nft >/dev/null && nft list tables >/dev/null 2>&1 && command -v curl >/dev/null; then
  for u in ab-session ab-other; do id "$u" >/dev/null 2>&1 || useradd -M -s /bin/bash "$u"; done
  python3 -m http.server 9222 --bind 127.0.0.1 >/dev/null 2>&1 & srv=$!; sleep 1
  as() { su -s /bin/bash "$1" -c 'curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:9222/' || true; }
  nft -f "$t/ab.nft"
  [ "$(as ab-session)" = 200 ] && ok "session user reaches the port" || bad "session user is blocked"
  [ "$(as ab-other)" != 200 ] && ok "another user is reset" || bad "another user reached the port through the filter"
  nft delete table inet agent_browser
  kill "$srv"
  # A real squatter: another user listens on the port first; the session user's start refuses it.
  su -s /bin/bash ab-other -c 'exec python3 -m http.server 9222 --bind 127.0.0.1' >/dev/null 2>&1 & sq=$!; sleep 1
  chmod 755 "$t"
  out=$(su -s /bin/bash ab-session -c "AGENT_BROWSER_STATE=$t/sq python3 -I $PWD/$script start" 2>&1 || true)
  grep -q "already taken" <<<"$out" && ok "start refuses a port another user really listens on" \
    || bad "start accepted another user's listener: $out"
  kill "$sq" 2>/dev/null || true
  python3 -m http.server 9222 --bind 127.0.0.1 >/dev/null 2>&1 & srv=$!; sleep 1
  [ "$(as ab-other)" = 200 ] && ok "without the filter another user connects (the check above is real)" \
    || bad "the port answered no one without the filter, so the test proves nothing"
  kill "$srv"
else
  echo "skip live filter test: needs root and nftables"
fi

echo "$fails failed"
[ "$fails" -eq 0 ]
