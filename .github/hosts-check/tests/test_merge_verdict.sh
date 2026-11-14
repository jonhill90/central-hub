#!/usr/bin/env bash
# Cases for .github/merge/verdict.py, the merge job's go or no-go (D-0042 rule 2).
# Each case writes the four API answers to a folder and checks the exit code and one word of the output.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
script="$root/.github/merge/verdict.py"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
head=1111111111111111111111111111111111111111
fail=0

# case NAME WANT(0|1) EXPECT_TEXT PR_JSON FILES_JSON CHECKS_JSON STATUS_JSON
case_() {
  local name=$1 want=$2 text=$3 dir="$work/$1" got out
  mkdir -p "$dir"
  printf '%s' "$4" > "$dir/pr.json"
  printf '%s' "$5" > "$dir/files.json"
  printf '%s' "$6" > "$dir/checks.json"
  printf '%s' "$7" > "$dir/status.json"
  set +e
  out=$(python3 -I "$script" "$head" "$dir")
  got=$?
  set -e
  if [[ $got != "$want" || $out != *"$text"* ]]; then
    echo "FAIL: $name: exit $got, output: $out" >&2
    fail=1
  else
    echo "ok   $name"
  fi
}

pr_ok="{\"state\":\"open\",\"draft\":false,\"base\":{\"ref\":\"main\"},\"head\":{\"sha\":\"$head\"},\"mergeable\":true,\"mergeable_state\":\"clean\"}"
files_ok='[{"filename":"docs/a.md"}]'
checks_ok='{"total_count":2,"check_runs":[{"name":"docs","status":"completed","conclusion":"success"},{"name":"outside-links","status":"completed","conclusion":"skipped"}]}'
status_none='{}'

case_ green 0 GREEN "$pr_ok" "$files_ok" "$checks_ok" "$status_none"
case_ moved-head 1 "not the one named" "${pr_ok/$head/2222222222222222222222222222222222222222}" "$files_ok" "$checks_ok" "$status_none"
case_ draft 1 "is a draft" "${pr_ok/\"draft\":false/\"draft\":true}" "$files_ok" "$checks_ok" "$status_none"
case_ closed 1 "not open" "${pr_ok/\"open\"/\"closed\"}" "$files_ok" "$checks_ok" "$status_none"
case_ other-base 1 "does not target main" "${pr_ok/\"main\"/\"release\"}" "$files_ok" "$checks_ok" "$status_none"
case_ conflict 1 "clean merge" "${pr_ok/\"clean\"/\"dirty\"}" "$files_ok" "$checks_ok" "$status_none"
case_ unknown-mergeable 1 "clean merge" "${pr_ok/\"mergeable\":true/\"mergeable\":null}" "$files_ok" "$checks_ok" "$status_none"
case_ failed-check 1 "check docs: failure" "$pr_ok" "$files_ok" "${checks_ok/\"success\"/\"failure\"}" "$status_none"
case_ pending-check 1 "is in_progress" "$pr_ok" "$files_ok" '{"total_count":1,"check_runs":[{"name":"docs","status":"in_progress","conclusion":null}]}' "$status_none"
case_ neutral-check 1 "check docs: neutral" "$pr_ok" "$files_ok" "${checks_ok/\"success\"/\"neutral\"}" "$status_none"
case_ no-checks 1 "no checks" "$pr_ok" "$files_ok" '{"total_count":0,"check_runs":[]}' "$status_none"
case_ unread-checks 1 "read 2 of 150" "$pr_ok" "$files_ok" "${checks_ok/\"total_count\":2/\"total_count\":150}" "$status_none"
case_ red-status 1 "commit status is failure" "$pr_ok" "$files_ok" "$checks_ok" '{"state":"failure","statuses":[{"context":"x","state":"failure"}]}'
many=$(python3 -I -c 'import json; print(json.dumps([{"filename": "f%d" % i} for i in range(100)]))')
case_ too-many-files 1 "100 or more" "$pr_ok" "$many" "$checks_ok" "$status_none"

exit "$fail"
