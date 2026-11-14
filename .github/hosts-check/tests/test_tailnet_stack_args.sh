#!/usr/bin/env bash
# tailnet-stack.sh refuses a malformed call before it reads a key or touches the box (exit 2, a usage line):
#   1. no argument, an unknown action, extra arguments after plan or log.
#   2. apply without the card ID and plan hash, with a card ID that is not cmsg_..., with a hash that is not
#      12 lowercase hex digits, with a hash of another length, or with extra arguments.
# Usage: .github/hosts-check/tests/test_tailnet_stack_args.sh   (needs bash)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
w=$root/hosts/ansible/roles/agent_box/files/tailnet-stack.sh
fail=0
refuse() { # description, arguments...
  local what=$1; shift
  out=$(bash "$w" "$@" 2>&1); rc=$?
  if [[ $rc -eq 2 && $out == *usage* ]]; then echo "ok   $what"; else echo "FAIL $what (rc=$rc)"; fail=1; fi
}
card=cmsg_01X43rfNYp4H1dL1V2dkfkwNBs2MstPeufRMzK1m6UU6FK
refuse "no argument"
refuse "unknown action" destroy
refuse "plan with an extra argument" plan now
refuse "log with an extra argument" log all
refuse "apply with no card and no hash" apply
refuse "apply with no hash" apply "$card"
refuse "apply with a card that is not cmsg_" apply abc123 0123456789ab
refuse "apply with a hash of capitals" apply "$card" 0123456789AB
refuse "apply with a short hash" apply "$card" 0123456789a
refuse "apply with a long hash" apply "$card" 0123456789abc
refuse "apply with an extra argument" apply "$card" 0123456789ab extra
exit "$fail"
