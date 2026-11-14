#!/usr/bin/env bash
# Test cases for the FOSS check (STD-0006): each case builds a small repository and expects
# check_components.py to pass or fail with a given message.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pass=0 fail=0

row() { # name verdict sources [kind]
  local kind=${4:-software}
  cat <<ROW
  - name: $1
    kind: $kind
    used-for: a test
    licence: Apache-2.0
    licence-source: https://example.org/LICENSE
    paid-edition: none found
    paid-edition-source: https://example.org/pricing
    verdict: $2
    exit-path: something else
    sources: $3
    checked: 2026-11-14
ROW
}

make_repo() { # register-body exceptions-body code-line
  local d="$work/r$((pass + fail))"
  mkdir -p "$d/docs/standards" "$d/hosts"
  printf 'components:\n%s\n' "$1" > "$d/docs/standards/components.yaml"
  if [ -n "$2" ]; then
    printf 'exceptions:\n%s\n' "$2" > "$d/docs/standards/foss-exceptions.yaml"
  else
    echo 'exceptions: []' > "$d/docs/standards/foss-exceptions.yaml"
  fi
  printf '%s\n' "$3" > "$d/hosts/main.yml"
  git -C "$d" init -q && git -C "$d" add -A
  echo "$d"
}

expect() { # name want(0|1) grep-text repo
  local out rc=0
  out=$(python3 -I "$here/check_components.py" "$4" 2>&1) || rc=$?
  if { [ "$2" = 0 ] && [ "$rc" = 0 ]; } || { [ "$2" = 1 ] && [ "$rc" = 1 ] && grep -qF -- "$3" <<<"$out"; }; then
    echo "ok   $1"; pass=$((pass + 1))
  else
    echo "FAIL $1 (rc $rc)"; printf '%s\n' "$out"; fail=$((fail + 1))
  fi
}

img='image: docker.io/library/postgres:18.6'

expect "a covered image passes" 0 "" "$(make_repo "$(row PostgreSQL pass '[image:docker.io/library/postgres]')" "" "$img")"
expect "an image with no row fails" 1 "no register row" "$(make_repo "$(row Other pass '[image:quay.io/x]')" "" "$img")"
expect "a comment line is not a source" 0 "" "$(make_repo "$(row Other pass '[image:quay.io/x]')" "" "# $img")"
expect "a field saying not checked fails" 1 "not checked" \
  "$(make_repo "$(row PostgreSQL pass '[image:docker.io/library/postgres]' | sed 's/none found/not checked/')" "" "$img")"
expect "a missing licence source fails" 1 "licence-source is missing" \
  "$(make_repo "$(row PostgreSQL pass '[image:docker.io/library/postgres]' | grep -v licence-source)" "" "$img")"
expect "a failing row with no exception fails" 1 "has no named exception" \
  "$(make_repo "$(row PostgreSQL fail '[image:docker.io/library/postgres]')" "" "$img")"
expect "a failing row with a pending exception passes" 0 "" \
  "$(make_repo "$(row PostgreSQL fail '[image:docker.io/library/postgres]')" "  - {component: PostgreSQL, state: pending, listed: a test}" "$img")"
expect "a kept exception needs the owner's time" 1 "kept needs decided" \
  "$(make_repo "$(row PostgreSQL fail '[image:docker.io/library/postgres]')" "  - {component: PostgreSQL, state: kept, decided: yes}" "$img")"
expect "an exception for a passing row fails" 1 "exception is not needed" \
  "$(make_repo "$(row PostgreSQL pass '[image:docker.io/library/postgres]')" "  - {component: PostgreSQL, state: pending, listed: a test}" "$img")"
expect "a hosted row needs kind hosted" 1 "verdict hosted goes with kind hosted" \
  "$(make_repo "$(row Hub hosted '[image:docker.io/]')" "" "$img")"
expect "a download address needs a row" 1 "url:get.helm.sh/helm-" \
  "$(make_repo "$(row Other pass '[image:quay.io/x]')" "" '    url: "https://get.helm.sh/helm-{{ v }}-linux-amd64.tar.gz"')"
expect "a templated host is the lab's own" 0 "" \
  "$(make_repo "$(row Other pass '[image:quay.io/x]')" "" '    url: "https://{{ name }}.example/api"')"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
