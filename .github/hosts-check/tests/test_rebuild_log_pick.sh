#!/usr/bin/env bash
# `rebuild log` shows the newest run that did more than a teardown, and names a newer teardown-only run in one line,
# so a `rebuild teardown` after a failed run can't hide that run's diag. Made-up logs.
set -euo pipefail
src=$(cd "$(dirname "$0")/../../.." && pwd)/hosts/ansible/roles/agent_box/files/rebuild.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
mkdir -p "$t/logs"
sed -n '/^if \[\[ \${1:-} == log && \$# -eq 1 \]\]; then$/,/^fi$/p' "$src" | sed "s|/var/lib/agent-box/rebuild-dev/logs|$t/logs|" > "$t/block.sh"
[ -s "$t/block.sh" ] || { echo "FAIL: block not found"; exit 1; }
check() { if [[ $2 == *"$3"* ]] && { [ -z "${4:-}" ] || [[ $2 != *"$4"* ]]; }; then echo "ok   $1"; else echo "FAIL $1: $2"; fail=1; fi; }
run() { bash -c 'set -euo pipefail; set -- log; . "$0"' "$t/block.sh" 2>&1 || true; }
out=$(run); check "no logs: says so" "$out" "no run other than a teardown"
printf '%s\n' '2026-11-18T07:12:39Z preflight start' '2026-11-18T07:43:12Z apps end rc=1 1200s' 'diag: example-app OutOfSync' > "$t/logs/rebuild-20261118T071239Z.log"
out=$(run); check "one full run is shown" "$out" "run: rebuild-20261118T071239Z.log" "teardown-only"
printf '%s\n' 'rebuild: central-hub 0000000' '2026-11-18T07:43:50Z teardown start' '2026-11-18T07:43:50Z teardown end rc=0 0s' > "$t/logs/rebuild-20261118T074350Z.log"
out=$(run)
check "a newer teardown-only run is skipped" "$out" "run: rebuild-20261118T071239Z.log"
check "the failed run's diag is still shown" "$out" "diag: example-app OutOfSync"
check "the teardown-only run is named in one line" "$out" "newer teardown-only run: rebuild-20261118T074350Z.log: 2026-11-18T07:43:50Z teardown end rc=0 0s"
printf '%s\n' '2026-11-18T08:00:00Z teardown start' '2026-11-18T08:00:20Z teardown end rc=0 20s' '2026-11-18T08:00:20Z preflight start' > "$t/logs/rebuild-20261118T080000Z.log"
out=$(run); check "a rebuild (teardown, then the stages) is a full run" "$out" "run: rebuild-20261118T080000Z.log" "teardown-only"
[ "$fail" = 0 ] || exit 1
echo "rebuild log pick: all checks passed"
