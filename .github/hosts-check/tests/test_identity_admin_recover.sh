#!/usr/bin/env bash
# Role k8s_identity's tasks/admin-recover.yml (real ansible, stand-in kubectl that logs every call) and the sign-in fallback of
# files/ensure-client.sh and files/ensure-user.sh. Fake values only.
#   1. An admin account signs in (env admin ok): nothing is stopped, started, applied or deleted.
#   2. Both refused: Keycloak is stopped (instances 0), one Job from Keycloak's own image runs `bootstrap-admin user` for c1-admin
#      with the password by secretKeyRef from sso-bootstrap-admin (no value in the manifest, the log or the output), Keycloak is started
#      again (instances 1) and waited for, the Job is deleted, the probe runs again and passes (two probes in all).
#   3. The Job does not complete: the run fails, and Keycloak is still started again and the Job deleted.
#   4. The probe errors (not a refusal): the run fails and changes nothing.
#   5. Check mode with both refused: only probes; nothing stopped or applied.
#   6. After a recovery (c1-admin signs in, env admin refused): nothing is done again.
#   7. ensure-client.sh and ensure-user.sh: env admin refused, c1-admin with the same password accepted: they go on, one try each.
# Usage: .github/hosts-check/tests/test_identity_admin_recover.sh   (needs ansible-playbook)
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
command -v ansible-playbook >/dev/null || { echo "skip: no ansible-playbook here"; exit 0; }
mkdir -p "$t/bin"
cat > "$t/bin/kubectl" <<'PY'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
j = " ".join(a)
stdin = sys.stdin.read() if ("apply" in a or "exec" in a) else ""
open(os.environ["KUBE_LOG"], "a").write(json.dumps({"args": a, "stdin": stdin if "apply" in a else ""}) + "\n")
if "get pod" in j:
    print("Running", end=""); sys.exit(0)
if "exec" in a and "bash" in a:
    cnt = os.environ["PROBE_COUNT"]
    c = int(open(cnt).read()) if os.path.exists(cnt) else 0
    open(cnt, "w").write(str(c + 1))
    print(open(os.environ["PROBE1" if c == 0 else "PROBE2"]).read(), end=""); sys.exit(0)
if "get statefulset" in j and "image" in j:
    print("quay.io/keycloak/keycloak:26.8.2", end=""); sys.exit(0)
if "get statefulset" in j:
    print("0", end=""); sys.exit(0)
if "wait job/" in j:
    sys.exit(1 if os.environ.get("JOB_FAILS") == "1" else 0)
sys.exit(0)
PY
chmod +x "$t/bin/kubectl"
cat > "$t/play.yml" <<'YML'
- hosts: localhost
  gather_facts: false
  tasks:
    - ansible.builtin.include_role:
        name: k8s_identity
        tasks_from: admin-recover.yml
YML
# run <env-admin state before> <recovery-admin state before> [ansible args]; the probe after a recovery says recovery-user ok.
run() {
  printf '%s\n' "admin-probe: env-user $1" "admin-probe: recovery-user $2" > "$t/p1"
  printf '%s\n' "admin-probe: env-user refused" "admin-probe: recovery-user ok" > "$t/p2"
  : > "$t/log"; rm -f "$t/count"; shift 2
  (cd "$root/hosts/ansible" && ANSIBLE_CONFIG=ansible.cfg PATH="$t/bin:$PATH" KUBE_LOG="$t/log" PROBE1="$t/p1" PROBE2="$t/p2" \
    PROBE_COUNT="$t/count" ansible-playbook -i localhost, -c local "$t/play.yml" "$@" > "$t/out" 2>&1)
  rc=$?
}
has() { grep -c -F -- "$1" "$t/log"; }
changes() { echo $(( $(has '"patch"') + $(has '"apply"') + $(has '"delete"') )); }

# 1
run ok refused; n=$(changes)
if [[ $rc -eq 0 && $n -eq 0 ]]; then ok "1. an admin account signs in: nothing stopped, started, applied or deleted"
else bad "1. rc=$rc changes=$n $(tail -n 8 "$t/out")"; fi

# 2
run refused refused
down=$(has 'instances\":0'); up=$(has 'instances\":1'); app=$(has '"apply"'); del=$(has '"delete"')
man=$(python3 -I -c 'import json, sys
for l in open(sys.argv[1]):
    d = json.loads(l)
    if "apply" in d["args"]: print(d["stdin"])' "$t/log")
ord=$(python3 -I -c 'import json, sys
c = [" ".join(json.loads(l)["args"]) for l in open(sys.argv[1])]
def i(s): return [k for k, x in enumerate(c) if s in x]
print(i("instances\":0")[0] < i("apply")[0] < i("wait job/")[0] < i("instances\":1")[0] < i("delete job")[0])' "$t/log" 2>/dev/null)
if [[ $rc -eq 0 && $down -eq 1 && $up -eq 1 && $app -eq 1 && $del -eq 1 && $ord == True && $(cat "$t/count") -eq 2 &&
      $man == *"bootstrap-admin"* && $man == *'"--username:env"'* && $man == *"c1-admin"* && $man == *'"key": "password"'* &&
      $man == *"sso-bootstrap-admin"* && $man == *"quay.io/keycloak/keycloak:26.8.2"* ]]; then
  ok "2. both refused: stop, one Job for c1-admin by secretKeyRef, start, delete, probe again (2 probes), in that order"
else bad "2. rc=$rc down=$down up=$up apply=$app del=$del order=$ord probes=$(cat "$t/count" 2>/dev/null) $(tail -n 8 "$t/out")"; fi

# 3
JOB_FAILS=1 run refused refused; up3=$(has 'instances\":1'); del3=$(has '"delete"')
if [[ $rc -ne 0 && $up3 -eq 1 && $del3 -eq 1 ]]; then ok "3. the Job does not complete: the run fails, Keycloak is started again, the Job deleted"
else bad "3. rc=$rc up=$up3 del=$del3 $(tail -n 8 "$t/out")"; fi

# 4
run error refused; n4=$(changes)
if [[ $rc -ne 0 && $n4 -eq 0 ]]; then ok "4. the probe errors: the run fails, nothing changed"; else bad "4. rc=$rc changes=$n4"; fi

# 5
run refused refused --check; n5=$(changes)
if [[ $rc -eq 0 && $n5 -eq 0 ]]; then ok "5. check mode: only probes"; else bad "5. rc=$rc changes=$n5 $(tail -n 8 "$t/out")"; fi

# 6
run refused ok; n6=$(changes)
if [[ $rc -eq 0 && $n6 -eq 0 ]]; then ok "6. c1-admin already signs in: nothing is done again"; else bad "6. rc=$rc changes=$n6"; fi

# 7
cat > "$t/kcadm.sh" <<'SH'
#!/usr/bin/env bash
# config: --user <u>; temp-admin is refused, c1-admin accepted; the user of every sign-in is logged.
case "$1" in
  config) u=""; while [[ $# -gt 0 ]]; do [[ $1 == --user ]] && u=$2; shift; done
          echo "$u" >> "$FAKE_USERS"
          if [[ $u == temp-admin ]]; then echo "Invalid user credentials [invalid_grant]" >&2; exit 1; fi; exit 0 ;;
  get) if [[ $2 == realms/* ]]; then exit 0; fi; printf 'abc\n'; exit 0 ;;
  update|create) exit 0 ;;
esac
SH
chmod +x "$t/kcadm.sh"
echo '{"clientId": "proxmox", "username": "signin-test"}' > "$t/body.json"
for s in ensure-client ensure-user; do
  if [[ $s == ensure-client ]]; then args="lab proxmox"; else args="lab signin-test"; fi
  : > "$t/users"
  # shellcheck disable=SC2086
  o=$(env KCADM="$t/kcadm.sh" FAKE_USERS="$t/users" KC_BOOTSTRAP_ADMIN_USERNAME=temp-admin KC_BOOTSTRAP_ADMIN_PASSWORD=hunter2 \
      bash -c "$(cat "$root/hosts/ansible/roles/k8s_identity/files/$s.sh")" "$s" $args < "$t/body.json" 2>&1); r=$?
  u=$(tr '\n' ' ' < "$t/users")
  if [[ $r -eq 0 && $u == "temp-admin c1-admin " && $o != *hunter2* ]]; then
    ok "7. $s: env admin refused, c1-admin with the same password accepted, one try each"
  else bad "7. $s: rc=$r users=[$u] [$o]"; fi
done

# no value anywhere
if ! grep -q -E 'hunter2|SECRETVALUE' "$t/log" "$t/out"; then ok "8. no password in the calls or the output"; else bad "8. a value shows"; fi
exit "$fail"
