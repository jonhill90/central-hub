#!/usr/bin/env bash
# files/ensure-realm-display-name.sh against a stand-in kcadm. Fake values only.
#   1. The live name differs: prints "updated" and asks kcadm to update realms/lab with displayName.
#   2. The live name is the wanted one: prints "unchanged" and does not update.
#   3. The first admin account is refused: the recovery admin is tried (two sign-ins), and the step still passes.
#   4. Both are refused: one fixed-phrase line, exit 1, none of kcadm's text.
# Usage: .github/hosts-check/tests/test_ensure_realm_display_name.sh
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
script=$root/hosts/ansible/roles/k8s_identity/files/ensure-realm-display-name.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
cat > "$t/kcadm.sh" <<'SH'
#!/usr/bin/env bash
case "$1" in
  config) echo x >> "$FAKE_CALLS"
          if [[ ${FAKE_REFUSE:-} == all ]] || { [[ ${FAKE_REFUSE:-} == first ]] && [[ $(wc -l < "$FAKE_CALLS") -eq 1 ]]; }; then echo "Invalid user credentials [invalid_grant] SECRETTEXT" >&2; exit 1; fi; exit 0 ;;
  get) echo "${FAKE_NAME:-}"; exit 0 ;;
  update) echo "$*" >> "$FAKE_UPDATES"; exit 0 ;;
esac
SH
chmod +x "$t/kcadm.sh"
run() { : > "$t/calls"; : > "$t/updates"; out=$(env KCADM="$t/kcadm.sh" KEYCLOAK_ADMIN=a KEYCLOAK_ADMIN_PASSWORD=b FAKE_CALLS="$t/calls" FAKE_UPDATES="$t/updates" "$@" bash -c "$(cat "$script")" ensure-realm-display-name lab "Hub sign-in" 2>&1); rc=$?; }

run FAKE_NAME="Lab sign-in"
if [[ $rc -eq 0 && $out == updated && $(cat "$t/updates") == *"realms/lab"*"displayName=Hub sign-in"* ]]; then ok "1. a different live name is updated"; else bad "1. rc=$rc [$out]"; fi
run FAKE_NAME="Hub sign-in"
if [[ $rc -eq 0 && $out == unchanged && ! -s "$t/updates" ]]; then ok "2. the same name is left alone"; else bad "2. rc=$rc [$out]"; fi
run FAKE_NAME="Lab sign-in" FAKE_REFUSE=first
if [[ $rc -eq 0 && $out == updated && $(wc -l < "$t/calls") -eq 2 ]]; then ok "3. a refused first admin falls back to the recovery admin"; else bad "3. rc=$rc [$out]"; fi
run FAKE_NAME="Lab sign-in" FAKE_REFUSE=all
if [[ $rc -eq 1 && $out == "ensure-realm-display-name: admin sign-in failed: refused (wrong username or password)" && $out != *SECRETTEXT* && ! -s "$t/updates" ]]; then ok "4. both refused: one fixed line, no kcadm text"; else bad "4. rc=$rc [$out]"; fi
exit $fail
