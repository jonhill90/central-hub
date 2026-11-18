#!/usr/bin/env bash
# Test cases for check_spec_line.py. Run from anywhere; the spec-line workflow runs it.
set -euo pipefail
cd "$(dirname "$0")/../../.."
check=$PWD/.github/spec-check/check_spec_line.py
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/repo/docs/specs"
: > "$work/repo/docs/specs/2026-10-example.md"
failed=0

expect() { # expect pass|fail <name> <files, one per line> <body>
  local want=$1 name=$2 got=pass
  printf '%b' "$3" >"$work/files"
  printf '%b' "$4" >"$work/body"
  python3 "$check" --root "$work/repo" --body "$work/body" --files "$work/files" >"$work/out" 2>&1 || got=fail
  if [ "$got" = "$want" ]; then
    echo "ok: $name"
  else
    echo "NOT OK: $name: expected $want, got $got"
    cat "$work/out"
    failed=1
  fi
}

H='hosts/ansible/README.md\n'
expect pass "a PR that does not touch hosts/ needs no line" 'docs/specs/README.md\n' '## Summary\n\n-\n'
expect fail "hosts/ with no line" "$H" '## Summary\n\n- a change\n'
expect pass "hosts/ with a Spec line naming a spec in the checkout" "$H" '## Spec\n\n- Spec: docs/specs/2026-10-example.md\n'
expect pass "a Spec line with backticks and no bullet" "$H" 'Spec: `docs/specs/2026-10-example.md`\n'
expect fail "a Spec line naming a file that is not there" "$H" '- Spec: docs/specs/2026-10-missing.md\n'
expect fail "the template's empty Spec line" "$H" '## Spec\n\n- Spec:\n'
expect fail "a Spec line that is prose" "$H" '- Spec: (the path of its spec)\n'
expect fail "a Spec line naming a path outside docs/specs" "$H" '- Spec: ../../etc/passwd\n'
expect pass "No spec with a reason" "$H" '- No spec: a one-line typo fix in a README\n'
expect fail "No spec with no reason" "$H" '- No spec:\n'
expect fail "No spec with a reason that is too short" "$H" '- No spec: small\n'
expect fail "the words only inside a sentence" "$H" 'There is no Spec: line here, and No spec: is not at the start of this line.\n'
expect pass "a hosts/ file among others" 'docs/runbooks/x.md\nhosts/rebuild-k8s.sh\n' '- No spec: renames a stage label only\n'
expect fail "hostsfile does not hide a real hosts/ file" 'hostsfile\nhosts/x\n' 'nothing\n'
expect pass "a file named hostsfile alone is not under hosts/" 'hostsfile\n' 'nothing\n'
exit $failed
