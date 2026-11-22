#!/usr/bin/env bash
# The signin-check wrapper (hosts/ansible/roles/agent_box/files/signin-check.sh), with stand-ins for git and the three check
# scripts (the real scripts have their own tests):
#   1. Usage: no action, an unknown action, extra arguments: exit 2, nothing run.
#   2. A missing signin-check.json or identity.env stops the run, naming the file, before any check.
#   3. A config that lacks a field, and an identity.env with no line for the test user, are refused before any check, and the
#      refusal names the missing key and no value.
#   4. A full run builds one private file per check (mode 0600, holding the password and the seed), runs the four, prints only
#      their lines and PASS, and leaves no temporary folder behind.
#   5. With no pve_base the Proxmox check does not run. 5b/5c: Grafana's name comes from grafana_base or from the Argo CD name (argocd
#      label swapped for grafana); with neither the run is refused before any check.
#   6. A failing check, and a check that exits non-zero without a FAIL line, make the run FAIL (exit 1).
#   7. log prints the newest run's lines.
#   8. The password and the seed never show in the output or the log.
# Usage: .github/hosts-check/tests/test_signin_check_wrapper.sh   (needs python3, flock)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

mkdir -p "$t/bin" "$t/keys/prod" "$t/work/state" "$t/work/central-hub" "$t/run"
cat > "$t/bin/git" <<S
#!/bin/bash
case "\$*" in
  *"remote get-url"*) echo https://example.invalid/central-hub.git ;;
  clone*)
    d=\${@: -1}; mkdir -p "\$d/.git"
    for s in roles/k8s_identity/files/jellyfin-signin-check.py roles/k8s_gitops/files/argocd-signin-check.py roles/proxmox_sso/files/proxmox-signin-check.py roles/k8s_observability/files/grafana-signin-check.py; do
      mkdir -p "\$d/hosts/ansible/\$(dirname "\$s")"; cp $t/stub-check.py "\$d/hosts/ansible/\$s"
    done ;;
  *rev-parse*) echo abc1234 ;;
esac
exit 0
S
cat > "$t/stub-check.py" <<'PY'
import json, os, stat, sys
body = json.load(open(sys.argv[1]))
mode = stat.S_IMODE(os.stat(sys.argv[1]).st_mode)
name = "jellyfin" if "jellyfin_base" in body else "argocd" if "argocd_base" in body else "grafana" if "grafana_base" in body else "proxmox"
open(os.environ["STUB_CALLS"], "a").write("%s mode=%o password=%s seed=%s user=%s\n" % (
    name, mode, body.get("password") == "pw-secret-value", body.get("seed") == "SEEDSECRETVALUE", body.get("user")))
mode_file = os.environ["STUB_FAIL"]
fails = open(mode_file).read().split() if os.path.exists(mode_file) else []
if name + ":crash" in fails:
    sys.exit(3)
for i in range(1, 4):
    bad = name + ":fail" in fails and i == 2
    print("%d step %d: HTTP 200 %s" % (i, i, "FAIL: stubbed" if bad else "ok"))
sys.exit(1 if name + ":fail" in fails else 0)
PY
chmod +x "$t/bin/git"
sed -e "s|^keys=.*|keys=$t/keys|" -e "s|^work=.*|work=$t/work|" -e "s|PATH=/usr/local/bin:|PATH=$t/bin:/usr/local/bin:|" \
    hosts/ansible/roles/agent_box/files/signin-check.sh > "$t/run/signin-check.sh"
if ! grep -q "^keys=$t/keys" "$t/run/signin-check.sh"; then echo "FAIL the test could not point the wrapper at its folders"; exit 1; fi
export STUB_CALLS=$t/calls STUB_FAIL=$t/failmode
run() { : > "$t/calls"; bash "$t/run/signin-check.sh" "$@" > "$t/out" 2>&1; rc=$?; out=$(cat "$t/out"); calls=$(cat "$t/calls"); }
conf() { printf '%s' "$1" > "$t/keys/prod/signin-check.json"; }
good='{"base":"https://sso.example.invalid","realm":"lab","user":"signin.test","expect_admin":true,"jellyfin_base":"https://jf.example.invalid","argocd_base":"https://argocd.example.invalid","pve_base":"https://pve.example.invalid"}'

run; [[ $rc -eq 2 && -z $calls ]] && ok "1a. no action: usage, exit 2" || bad "1a. rc=$rc $out"
run apply; [[ $rc -eq 2 ]] && ok "1b. an unknown action: exit 2" || bad "1b. rc=$rc $out"
run run extra; [[ $rc -eq 2 ]] && ok "1c. extra arguments: exit 2" || bad "1c. rc=$rc $out"

run run; [[ $rc -eq 1 && $out == *signin-check.json* && -z $calls ]] && ok "2a. a missing signin-check.json stops the run" || bad "2a. rc=$rc $out"
conf "$good"
run run; [[ $rc -eq 1 && $out == *identity.env* && -z $calls ]] && ok "2b. a missing identity.env stops the run" || bad "2b. rc=$rc $out"

printf 'PASSWORD_OWNER=x\n' > "$t/keys/prod/identity.env"
run run; [[ $rc -eq 1 && $out == *PASSWORD_SIGNIN_TEST* && -z $calls ]] && ok "3a. no line for the test user is refused, naming the key" || bad "3a. rc=$rc $out"
printf '# comment\nPASSWORD_SIGNIN_TEST=%s\nTOTP_SIGNIN_TEST=%s\n' pw-secret-value SEEDSECRETVALUE > "$t/keys/prod/identity.env"
conf '{"base":"https://sso.example.invalid","realm":"lab","user":"signin.test"}'
run run; [[ $rc -eq 1 && $out == *"lacks: jellyfin_base"* && -z $calls ]] && ok "3b. a config without a field is refused before any check" || bad "3b. rc=$rc $out"

conf "$good"; rm -f "$t/failmode"
run run
if [[ $rc -eq 0 && $out == *"signin-check: PASS"* && $(grep -c ' mode=600 password=True seed=True user=signin.test' <<< "$calls") -eq 4 ]]; then
  ok "4a. four checks ran on private files holding the password and seed, and the run passed"
else bad "4a. rc=$rc $out / $calls"; fi
[[ -z $(find "$t/work/state" -maxdepth 1 -name 'signin-check.*' -type d) ]] && ok "4b. no temporary folder is left behind" || bad "4b. a temporary folder stayed"
[[ $out == *"== jellyfin"* && $out == *"== argocd"* && $out == *"== proxmox"* && $out == *"== grafana"* && $out == *"1 step 1: HTTP 200 ok"* ]] && ok "4c. the checks' own lines are printed" || bad "4c. $out"
cp "$t/out" "$t/out-pass"

conf "$(python3 -I -c 'import json, sys; d = json.loads(sys.argv[1]); d.pop("pve_base"); print(json.dumps(d))' "$good")"
run run; [[ $rc -eq 0 && $calls != *proxmox* && $(wc -l <<< "$calls") -eq 3 ]] && ok "5. with no pve_base the Proxmox check does not run" || bad "5. rc=$rc $calls"

conf "$(python3 -I -c 'import json, sys; d = json.loads(sys.argv[1]); d["grafana_base"] = "https://graf.example.invalid"; print(json.dumps(d))' "$good")"
run run; seen=$(grep -c "^grafana " <<< "$calls")
[[ $rc -eq 0 && $seen -eq 1 ]] && ok "5b. grafana_base in the config names Grafana's address; without it the Argo CD name with argocd swapped for grafana" || bad "5b. rc=$rc $calls"
conf "$(python3 -I -c 'import json, sys; d = json.loads(sys.argv[1]); d["argocd_base"] = "https://argo.example.invalid"; print(json.dumps(d))' "$good")"
run run; [[ $rc -eq 1 && $out == *"no grafana_base"* && -z $calls ]] && ok "5c. no grafana_base and no argocd label to swap: refused before any check" || bad "5c. rc=$rc $out"

conf "$good"; echo "argocd:fail" > "$t/failmode"
run run; [[ $rc -eq 1 && $out == *"signin-check: FAIL"* && $out == *"FAIL: stubbed"* ]] && ok "6a. a failing check fails the run" || bad "6a. rc=$rc $out"
echo "proxmox:crash" > "$t/failmode"
run run; [[ $rc -eq 1 && $out == *"proxmox: exit 3"* && $out == *"signin-check: FAIL"* ]] && ok "6b. a check that exits non-zero with no FAIL line fails the run" || bad "6b. rc=$rc $out"
rm -f "$t/failmode"

run log; [[ $rc -eq 0 && $out == *"run: run-"* && $out == *"== argocd"* ]] && ok "7. log prints the newest run's lines" || bad "7. rc=$rc $out"

if ! cat "$t"/out* "$t"/work/signin-check/logs/* | grep -Eq 'pw-secret-value|SEEDSECRETVALUE'; then ok "8. no password or seed in the output or the log"; else bad "8. a secret value showed"; fi
exit "$fail"
