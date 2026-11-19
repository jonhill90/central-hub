#!/usr/bin/env bash
# hosts/rebuild-k8s.sh stage_failure_lines: when a stage fails, the short log gets that stage's last Ansible task line,
# its fatal:/FAILED!/msg/stderr lines (at most 20), scrubbed of secrets, from that stage's part of the raw log only; a stage
# with no Ansible lines gets its last 5 lines; an empty stage says so. Also: the main loop calls it only on a failed stage.
# Usage: .github/hosts-check/tests/test_rebuild_failure_lines.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
repo=$PWD; script=hosts/rebuild-k8s.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
fn=$(sed -n '/^stage_failure_lines() {/,/^}/p' "$script")
[ -n "$fn" ] || { echo "FAIL could not read stage_failure_lines from $script"; exit 1; }
cat > "$t/raw" <<'R'
===== apps
TASK [apps | other stage] ***
fatal: [node]: FAILED! => {"msg": "must not appear"}
===== identity-keycloak
TASK [operator | Upstream files, checked against their pinned sha256] ***
fatal: [node]: FAILED! => {"msg": "Request failed: <urlopen error [Errno 111] Connection refused>"}
"stderr": "login failed password=hunter2 token=abcdef.0123456789abcdef"
"msg": "ssh to 10.1.30.44 failed, also tried box-7.tailab12.ts.net and 192.168.4.9"
PLAY RECAP ***
===== later
fatal: [later-node]: FAILED! => {"msg": "later stage must not show"}
===== checks
some plain line one
some plain line two
===== empty
R
run() { # stage ; stdout: the log
  ( export repo raw="$t/raw" log="$t/log"; : > "$log"; eval "$fn"; stage_failure_lines "$1" >/dev/null 2>&1; echo "rc=$?" > "$t/rc"; cat "$log" ); }
out=$(run identity-keycloak)
{ [[ $out == *"identity-keycloak: fail: TASK [operator | Upstream files"* && $out == *"identity-keycloak: fail: fatal: [<host>]: FAILED!"*"Connection refused"* ]] &&
  [[ $out != *"must not appear"* ]]; } && ok "1 the stage's task and fatal lines are logged, another stage's are not" || bad "1 $out"
{ [[ $out != *hunter2* && $out != *0123456789abcdef* && $out == *"<redacted>"* ]]; } && ok "2 secrets are scrubbed" || bad "2 $out"
{ [[ $out != *"later stage must not show"* ]]; } && ok "1b a later stage's fatal line does not show under the failed stage (the section ends at the next =====)" || bad "1b the section did not end: $out"
{ [[ $out != *"fatal: [node]"* && $out == *"fatal: [<host>]: FAILED!"* ]]; } && ok "2b the host in fatal: [host] is masked" || bad "2b $out"
{ [[ $out != *10.1.30.44* && $out != *192.168.4.9* && $out == *"<ip>"* ]]; } && ok "2c IPv4 addresses are masked" || bad "2c $out"
{ [[ $out != *tailab12* && $out != *box-7* && $out == *"<tailnet-name>"* ]]; } && ok "2d *.ts.net names are masked" || bad "2d $out"
out=$(run checks); { [[ $out == *"checks: fail: some plain line two"* ]]; } && ok "3 a stage with no Ansible lines gets its last lines" || bad "3 $out"
out=$(run empty); { [[ $out == *"empty: fail: no output from the stage"* ]]; } && ok "4 an empty stage says so" || bad "4 $out"
{ [ "$(cat "$t/rc")" = rc=0 ]; } && ok "5 the function never fails the caller" || bad "5 rc $(cat "$t/rc")"
if sed -n '/^  if \[ "\$rc" -ne 0 \]; then$/,/^  fi$/p' "$script" | grep -q '^    stage_failure_lines "\$s"$'; then
  ok "6 the main loop calls it inside the failed-stage branch"
else bad "6 the main loop does not call it on a failed stage"; fi
exit "$fail"
