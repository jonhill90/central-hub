#!/usr/bin/env bash
# `tailnet-policy.sh log` shows the newest run's summary, and, when that run failed, its scrubbed error lines:
#   1. a failed plan: the Error: line and the lines after it show, with addresses, e-mail addresses and tailnet names replaced.
#   2. the rest of the log (a policy line naming a host) does not show.
#   3. a passed run shows no error block.
# The script's fixed paths are pointed at a temp folder in a copy; the script itself is not changed.
# Usage: .github/hosts-check/tests/test_tailnet_policy_log.sh   (needs bash)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
src=$root/hosts/ansible/roles/agent_box/files/tailnet-policy.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
check() { if [[ $2 == ok ]]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
sed "s#^work=/var/lib/agent-box#work=$t#" "$src" > "$t/w.sh"
mkdir -p "$t/logs/tailnet-policy"
l=$t/logs/tailnet-policy
printf '%s\n' '{"stack": "tailnet-policy", "result": "FAIL: plan"}' > "$l/summary.jsonl"
printf '%s\n' 'tofu: refreshing' 'rule 100.64.1.2 grants tcp:22' 'Error: Failed to fetch ACL' '' '  unexpected status 403 for 10.0.0.5 from alice@example.com on tail1234.ts.net' > "$l/run-20261118T000000Z.txt"
out=$(bash "$t/w.sh" log 2>&1)
check "failed plan shows the Error line" "$([[ $out == *"Failed to fetch ACL"* ]] && echo ok)"
check "failed plan shows the status line" "$([[ $out == *"status 403"* ]] && echo ok)"
check "address replaced" "$([[ $out == *"<ip>"* && $out != *"10.0.0.5"* ]] && echo ok)"
check "e-mail replaced" "$([[ $out != *"alice@example.com"* ]] && echo ok)"
check "tailnet name replaced" "$([[ $out != *"tail1234.ts.net"* ]] && echo ok)"
check "policy line before the error stays off" "$([[ $out != *"grants tcp:22"* ]] && echo ok)"
printf '%s\n' '{"stack": "tailnet-policy", "result": "passed"}' > "$l/summary.jsonl"
out=$(bash "$t/w.sh" log 2>&1)
check "passed run shows no error block" "$([[ $out != *"errors (scrubbed)"* ]] && echo ok)"
exit "$fail"
