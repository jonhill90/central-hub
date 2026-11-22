#!/usr/bin/env bash
# files/ensure-client.sh against a stand-in kcadm: when a step fails it prints one fixed-phrase reason line and exits 1,
# and never prints kcadm's own error text (which can hold the client JSON, with its secrets). Fake values only.
#   1. An existing client that updates: prints "updated", exit 0. A missing one: "created".
#   2. The update fails with "Conflict ... SECRETVALUE": "ensure-client: update failed: conflict", no SECRETVALUE.
#   3. The create fails with an unknown error: "unclassified", still no error text.
#   4. The client lookup fails (forbidden): "client lookup failed: forbidden".
#   5. A lookup whose first line is followed by more lines still takes the first (no pipe into head).
# Usage: .github/hosts-check/tests/test_ensure_client_reason.sh
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
script=$root/hosts/ansible/roles/k8s_identity/files/ensure-client.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
cat > "$t/kcadm.sh" <<'SH'
#!/usr/bin/env bash
# $1 = config|get|update|create; FAKE_FAIL names the step that fails, FAKE_ERR its error text; FAKE_IDS the lookup's output.
case "$1" in
  config) exit 0 ;;
  get) if [[ $2 == realms/* ]]; then exit 0; fi
       if [[ ${FAKE_FAIL:-} == lookup ]]; then echo "${FAKE_ERR:-}" >&2; exit 1; fi
       printf '%b' "${FAKE_IDS:-}"; exit 0 ;;
  update) if [[ ${FAKE_FAIL:-} == update ]]; then echo "${FAKE_ERR:-}" >&2; exit 1; fi; exit 0 ;;
  create) if [[ ${FAKE_FAIL:-} == create ]]; then echo "${FAKE_ERR:-}" >&2; exit 1; fi; exit 0 ;;
esac
SH
chmod +x "$t/kcadm.sh"
echo '{"clientId": "proxmox", "secret": "SECRETVALUE"}' > "$t/body.json"
run() { out=$(env KCADM="$t/kcadm.sh" KEYCLOAK_ADMIN=a KEYCLOAK_ADMIN_PASSWORD=b "$@" bash -c "$(cat "$script")" ensure-client lab proxmox < "$t/body.json" 2>&1); rc=$?; }

run FAKE_IDS='abc\n'; [[ $rc -eq 0 && $out == updated ]] && r1a=1 || r1a=0
run FAKE_IDS=''; [[ $rc -eq 0 && $out == created ]] && r1b=1 || r1b=0
if [[ $r1a -eq 1 && $r1b -eq 1 ]]; then ok "1. existing client: updated; missing client: created"; else bad "1. $r1a $r1b"; fi

run FAKE_IDS='abc\n' FAKE_FAIL=update FAKE_ERR='Conflict detected {"secret":"SECRETVALUE"}'
if [[ $rc -eq 1 && $out == "ensure-client: update failed: conflict"* && $out != *SECRETVALUE* ]]; then ok "2. update fails: conflict, no error text"
else bad "2. rc=$rc [$out]"; fi

run FAKE_IDS='' FAKE_FAIL=create FAKE_ERR='odd failure SECRETVALUE'
if [[ $rc -eq 1 && $out == "ensure-client: create failed: unclassified"* && $out != *SECRETVALUE* ]]; then ok "3. create fails: unclassified, no error text"
else bad "3. rc=$rc [$out]"; fi

run FAKE_FAIL=lookup FAKE_ERR='403 Forbidden SECRETVALUE'
if [[ $rc -eq 1 && $out == "ensure-client: client lookup failed: forbidden"* && $out != *SECRETVALUE* ]]; then ok "4. lookup fails: forbidden"
else bad "4. rc=$rc [$out]"; fi

run FAKE_IDS='abc\ndef\nghi\n'
if [[ $rc -eq 0 && $out == updated ]]; then ok "5. several lines from the lookup: the first is used"; else bad "5. rc=$rc [$out]"; fi
exit "$fail"
