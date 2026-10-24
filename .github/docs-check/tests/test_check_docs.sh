#!/usr/bin/env bash
# Test cases for check_docs.py (D-0019). Each case copies one good record, breaks it one way,
# and expects the check to fail with a given message. Usage: test_check_docs.sh
set -u
here=$(cd "$(dirname "$0")/.." && pwd); pass=0; fail=0
good='---
id: D-0001
title: Test
status: proposed
date: 2026-10-23
decision-makers: [jon]
proposed-by: drafting-agent
waits-on: []
supersedes: []
superseded-by:
revisit-when: never
---
# Test
'
case_() { # name, sed expression applied to the good record, expected text ("" = expect pass)
  d=$(mktemp -d); mkdir -p "$d/docs/decisions"
  printf '%s' "$good" | sed "$2" > "$d/docs/decisions/0001-test.md"
  printf '| D-0001 | [Test](0001-test.md) | proposed | — | 2026-10-23 |\n' > "$d/docs/decisions/README.md"
  out=$(python3 "$here/check_docs.py" "$d" 2>&1); rc=$?
  if { [ -z "$3" ] && [ $rc -eq 0 ]; } || { [ -n "$3" ] && [ $rc -ne 0 ] && grep -q -- "$3" <<<"$out"; }; then
    pass=$((pass+1)); echo "ok   $1"
  else fail=$((fail+1)); echo "FAIL $1"; echo "$out" | sed 's/^/     /'; fi
  rm -rf "$d"
}
case_ "good record passes"            's/^//'                                  ""
case_ "colon-space in a plain value"   's/^revisit-when: never/revisit-when: a, plus: b/' "not valid YAML"
case_ "duplicate key"                  's/^status: proposed/status: proposed\nstatus: accepted/' "not valid YAML"
case_ "yes is a string, not true"      's/^revisit-when: never/revisit-when: yes/'   ""
case_ "status word not allowed"        's/^status: proposed/status: approved/'      "status"
case_ "id does not match file name"    's/^id: D-0001/id: D-0002/'                 "does not match file name"
case_ "date not YYYY-MM-DD"            's/^date: 2026-10-23/date: 23 Oct 2026/'     "date"
case_ "accepted without evidence"      's/^status: proposed/status: accepted/'      "accepted-evidence"
case_ "unknown field"                  's/^title: Test/title: Test\ncolour: blue/'  "Additional properties"
case_ "waits-on a missing record"      's/^waits-on: \[\]/waits-on: [D-0099]/'      "has no record"
echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
