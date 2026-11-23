#!/usr/bin/env bash
# files/ensure-client.sh against a stand-in kcadm: when a step fails it prints one fixed-phrase reason line and exits 1,
# and never prints kcadm's own error text (which can hold the client JSON, with its secrets). Fake values only.
#   1. An existing client that updates: prints "updated", exit 0. A missing one: "created".
#   2. The update fails with "Conflict ... SECRETVALUE": "ensure-client: update failed: conflict", no SECRETVALUE.
#   3. The create fails with an unknown error: "unclassified", still no error text.
#   4. The client lookup fails (forbidden): "client lookup failed: forbidden".
#   5. A lookup whose first line is followed by more lines still takes the first (no pipe into head).
#   7. Admin sign-in refused with "Invalid user credentials [invalid_grant]" (kcadm's text for a wrong password): the line
#      says "admin sign-in failed: refused (invalid_grant: wrong username or password, or a disabled or locked account)", the script asked once (no five minutes of retries),
#      and the text "invalid input" is not used for it. A sign-in that fails for another reason is still retried.
#   6. The role's assert task (tasks/clients.yml, cut out and run with real ansible): every client passed -> the task
#      passes (an empty fail_msg would be an error); one failed -> the run fails with its reason line and no secret;
#      a result with no rc -> the failure names the exit as none, no templating error. Needs ansible-playbook.
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
  config) echo x >> "${FAKE_CALLS:-/dev/null}"
          if [[ ${FAKE_FAIL:-} == signin ]]; then echo "${FAKE_ERR:-}" >&2; exit 1; fi; exit 0 ;;
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

# 7
: > "$t/calls"
run FAKE_FAIL=signin FAKE_ERR='Invalid user credentials [invalid_grant] SECRETVALUE' FAKE_CALLS="$t/calls"; n7=$(wc -l < "$t/calls" | tr -d ' ')
if [[ $rc -eq 1 && $out == "ensure-client: admin sign-in failed: refused (invalid_grant: wrong username or password, or a disabled or locked account)"* && $out != *SECRETVALUE* && $n7 -eq 1 ]]; then
  ok "7. wrong admin password: named as such, asked once, no error text"
else bad "7. rc=$rc calls=$n7 [$out]"; fi

# 6
if ! command -v ansible-playbook >/dev/null; then echo "skip 6. no ansible-playbook here"; exit "$fail"; fi
python3 -I - "$root/hosts/ansible/roles/k8s_identity/tasks/clients.yml" "$t" <<'PY'
import sys, re
s = open(sys.argv[1]).read()
i = s.index("- name: clients | Each client was made or updated"); j = s.index("- name: clients | Remove the controller")
blk = "\n".join(("    " + l) if l else l for l in s[i:j].rstrip().split("\n"))
cases = {
 "pass": "[{rc: 0, stdout_lines: [updated], __result: {__client: a}}]",
 "fail": "[{rc: 1, stdout_lines: ['ensure-client: update failed: conflict (x)'], __result: {__client: proxmox}, invocation: {module_args: {stdin: SECRETVALUE}}}, {rc: 0, __result: {__client: b}}]",
 "norc": "[{stdout_lines: [], __result: {__client: x}}]",
}
for n, res in cases.items():
    open(f"{sys.argv[2]}/{n}.yml", "w").write("- hosts: localhost\n  gather_facts: false\n  vars:\n    ansible_check_mode: false\n    k8s_identity_client_ensured: {results: %s}\n  tasks:\n%s\n" % (res, blk))
PY
pb() { ansible-playbook -i localhost, -c local "$t/$1.yml" > "$t/$1.out" 2>&1; echo $?; }
rp=$(pb pass); rf=$(pb fail); rn=$(pb norc)
if [[ $rp -eq 0 && $rf -ne 0 && $rn -ne 0 ]] && grep -q "update failed: conflict" "$t/fail.out" && ! grep -q SECRETVALUE "$t/fail.out" &&
   grep -q "exited none without a reason line" "$t/norc.out" && ! grep -q "templating\|NoneType" "$t/pass.out" "$t/fail.out" "$t/norc.out"; then
  ok "6. assert task: passes when all passed; fails with the reason line, no secret; no rc is named, not a templating error"
else bad "6. pass=$rp fail=$rf norc=$rn $(tail -n 5 "$t/pass.out" "$t/norc.out")"; fi
exit "$fail"
