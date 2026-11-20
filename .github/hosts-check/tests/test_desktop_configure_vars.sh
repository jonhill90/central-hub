#!/bin/bash
# Tests for the values `desktop configure` passes to playbooks/desktop.yml (hosts/ansible/roles/agent_box/files/desktop.sh)
# and the trust check's default names (role desktop, defaults/main.yml):
#   1. the zone is read from the prod inventory's k8s_gateway_zone, wherever it sits, and passed as
#      desktop_trust_check_zone; no zone, two different zones or a templated value stops the run;
#   2. with a zone and desktop_trust_check_reach on, the role's default names are <app>.<zone> for the gateway name
#      check's apps; with reach off (the default) or no zone, none;
#   3. `desktop destroy` forgets the destroyed VM's SSH host key, so the rebuilt VM's first configure accepts its new one.
# The wrapper's Python is cut from desktop.sh itself, so the test runs the shipped text.
set -euo pipefail
here=$(cd "$(dirname "$0")/../../.." && pwd)
wrapper=$here/hosts/ansible/roles/agent_box/files/desktop.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

awk '/"\$prodinv" .*<<'"'"'PY'"'"'$/ {on=1; next} on && /^PY$/ {exit} on {print}' "$wrapper" >"$t/vars.py"
[[ -s $t/vars.py ]] || { echo "FAIL: the configure Python was not found in desktop.sh"; exit 1; }
echo '{"address": "192.0.2.91", "rdp_source": "192.0.2.5/32"}' >"$t/settings.json"
echo "chain" >"$t/chain.crt"

fails=0
run() { python3 -I "$t/vars.py" "$t/settings.json" "$t/inv.json" "$t/extra.json" "$t/chain.crt" "$t/prod.yml" "" "$t/test-login.json"; }
case_ok() { # description, inventory YAML, wanted zone
  printf '%s\n' "$2" >"$t/prod.yml"; rm -f "$t/extra.json"
  if run 2>"$t/err" && [[ $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["desktop_trust_check_zone"])' "$t/extra.json") == "$3" ]]; then
    echo "ok   $1"
  else echo "FAIL: $1"; cat "$t/err"; fails=$((fails + 1)); fi
}
case_stop() { # description, inventory YAML
  printf '%s\n' "$2" >"$t/prod.yml"; rm -f "$t/extra.json"
  if run 2>"$t/err"; then echo "FAIL: $1 (the run went on)"; fails=$((fails + 1))
  elif grep -q 'k8s_gateway_zone' "$t/err" && [[ ! -e $t/extra.json ]]; then echo "ok   $1"
  else echo "FAIL: $1 (wrong message or a file written)"; cat "$t/err"; fails=$((fails + 1)); fi
}

case_ok "the zone from the k8s_nodes group's vars" \
  'all: {children: {k8s_nodes: {vars: {k8s_gateway_zone: lab.example.com, k8s_certs_zone: "{{ k8s_gateway_zone }}"}}}}' lab.example.com
case_ok "the same zone in two places counts once" \
  'all: {vars: {k8s_gateway_zone: lab.example.com}, children: {k8s_nodes: {vars: {k8s_gateway_zone: lab.example.com}}}}' lab.example.com
case_stop "no zone stops the run" 'all: {children: {k8s_nodes: {vars: {k8s_gateway_zone: ""}}}}'
case_stop "two zones stop the run" \
  'all: {vars: {k8s_gateway_zone: a.example.com}, children: {k8s_nodes: {vars: {k8s_gateway_zone: b.example.com}}}}'
case_stop "a templated zone stops the run" 'all: {vars: {k8s_gateway_zone: "{{ lab_zone }}"}}'
printf 'all: {vars: {k8s_gateway_zone: lab.example.com}}\n' >"$t/prod.yml"; run
if python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["desktop_admin_user"]=="admin" and d["k8s_node_trust_enabled"] is True and d["k8s_node_trust_chain_file"].endswith("chain.crt")' "$t/extra.json"; then
  echo "ok   the other values are as before"
else echo "FAIL: the other values changed"; fails=$((fails + 1)); fi

# The role's default names, rendered by Ansible from defaults/main.yml.
cat >"$t/render.yml" <<YML
- hosts: localhost
  connection: local
  gather_facts: false
  vars_files: [$here/hosts/ansible/roles/desktop/defaults/main.yml]
  tasks:
    - ansible.builtin.copy: {content: "{{ desktop_trust_check_names | to_json }}", dest: "$t/names.json", mode: "0600"}
YML
names() { ANSIBLE_LOCALHOST_WARNING=False ansible-playbook -i localhost, -e ansible_python_interpreter=auto_silent "$t/render.yml" "$@" >/dev/null && cat "$t/names.json"; }
want='["grafana.lab.example.com", "argocd.lab.example.com", "sso.lab.example.com", "jellyfin.lab.example.com", "ntfy.lab.example.com"]'
got=$(names -e desktop_trust_check_zone=lab.example.com -e desktop_trust_check_reach=true)
[[ $got == "$want" ]] && echo "ok   with a zone and reach on, the names are each app's short name" || { echo "FAIL: names with a zone: $got"; fails=$((fails + 1)); }
got=$(names -e desktop_trust_check_zone=lab.example.com)
[[ $got == "[]" ]] && echo "ok   with a zone and reach off (the default), no names" || { echo "FAIL: names with reach off: $got"; fails=$((fails + 1)); }
got=$(names)
[[ $got == "[]" ]] && echo "ok   without a zone, no names" || { echo "FAIL: names without a zone: $got"; fails=$((fails + 1)); }
gw=$(python3 -I -c 'import sys,yaml; print(" ".join(yaml.safe_load(open(sys.argv[1]))["nameCheck"]["apps"]))' "$here/hosts/kubernetes/home/c1/apps/gateway/values.yaml")
role=$(python3 -I -c 'import sys,yaml; print(" ".join(yaml.safe_load(open(sys.argv[1]))["desktop_trust_check_apps"]))' "$here/hosts/ansible/roles/desktop/defaults/main.yml")
[[ $gw == "$role" ]] && echo "ok   the apps are the gateway name check's apps" || { echo "FAIL: apps differ: gateway '$gw', desktop '$role'"; fails=$((fails + 1)); }

# A destroy forgets the destroyed VM's host key and keeps every other line (forget_host_key, cut from desktop.sh).
awk '/^forget_host_key\(\) \{$/ {on=1} on {print} on && /^}$/ {exit}' "$wrapper" >"$t/forget.sh"
grep -q 'ssh-keygen -R' "$t/forget.sh" || { echo "FAIL: forget_host_key was not found in desktop.sh"; fails=$((fails + 1)); }
grep -q '^      forget_host_key$' "$wrapper" && echo "ok   destroy calls forget_host_key" || { echo "FAIL: destroy does not call forget_host_key"; fails=$((fails + 1)); }
mkdir -p "$t/w/.ssh"
ssh-keygen -q -t ed25519 -N "" -f "$t/k1"; ssh-keygen -q -t ed25519 -N "" -f "$t/k2"
{ echo "192.0.2.91 $(cut -d' ' -f1,2 "$t/k1.pub")"; echo "192.0.2.92 $(cut -d' ' -f1,2 "$t/k2.pub")"; } >"$t/w/.ssh/known_hosts"
out=$(work=$t/w settings=$t/settings.json bash -c "set -euo pipefail; source '$t/forget.sh'; forget_host_key")
if ! grep -q '^192\.0\.2\.91 ' "$t/w/.ssh/known_hosts" && grep -q '^192\.0\.2\.92 ' "$t/w/.ssh/known_hosts" \
   && [[ ! -e $t/w/.ssh/known_hosts.old && $out == *forgotten* ]]; then
  echo "ok   destroy forgets the desktop's host key and keeps the others"
else echo "FAIL: forget_host_key: $out"; cat "$t/w/.ssh/known_hosts"; fails=$((fails + 1)); fi
rm -f "$t/w/.ssh/known_hosts"
if work=$t/w settings=$t/settings.json bash -c "set -euo pipefail; source '$t/forget.sh'; forget_host_key" >/dev/null; then
  echo "ok   with no known_hosts yet, destroy goes on"
else echo "FAIL: forget_host_key without known_hosts"; fails=$((fails + 1)); fi

# configure-test: two random passwords go to the keys file (0600) and the extra vars, and the box's own address
# becomes an extra RDP source. The plain configure writes neither.
printf 'all: {vars: {k8s_gateway_zone: lab.example.com}}\n' >"$t/prod.yml"
echo '{"address": "127.0.0.1", "rdp_source": "192.0.2.5/32"}' >"$t/settings.json"
rm -f "$t/test-login.json" "$t/extra.json"
(umask 077; python3 -I "$t/vars.py" "$t/settings.json" "$t/inv.json" "$t/extra.json" "$t/chain.crt" "$t/prod.yml" 1 "$t/test-login.json")
if python3 -I - "$t/extra.json" "$t/test-login.json" <<'PY'
import json, os, stat, sys
e, k = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
assert e["desktop_test_login"] is True and e["desktop_rdp_extra_sources"] == ["127.0.0.1/32"]
assert e["desktop_test_login_password"] == k["login_password"] and e["desktop_test_rdp_password"] == k["rdp_password"]
assert k["login_password"] != k["rdp_password"] and len(k["rdp_password"]) >= 24
assert stat.S_IMODE(os.stat(sys.argv[2]).st_mode) == 0o600 and stat.S_IMODE(os.stat(sys.argv[1]).st_mode) == 0o600
PY
then echo "ok   configure-test makes two different passwords, 0600, and the box as an extra source"
else echo "FAIL: configure-test values"; fails=$((fails + 1)); fi
rm -f "$t/test-login.json"; run
[[ ! -e $t/test-login.json ]] && ! grep -q desktop_test_login "$t/extra.json" && echo "ok   plain configure makes no test login" || { echo "FAIL: plain configure wrote a test login"; fails=$((fails + 1)); }

# rdp-check (cut from desktop.sh) against a stand-in that answers like an RDP server: X.224 confirm choosing
# CredSSP, then TLS. It must print the protocol and the handshake, and fail with a clear line on a closed port.
awk '/^rdp_check\(\) \{$/ {on=1} on {print} on && /^}$/ {exit}' "$wrapper" >"$t/rdp.sh"
python3 -I - "$t" <<'PY'
import os, socket, ssl, subprocess, sys
t = sys.argv[1]
subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=stub",
                "-keyout", t + "/s.key", "-out", t + "/s.crt"], check=True, capture_output=True)
srv = socket.socket(); srv.bind(("127.0.0.1", 0)); srv.listen(1)
open(t + "/port", "w").write(str(srv.getsockname()[1]))
if os.fork() == 0:
    c, _ = srv.accept(); c.recv(512)
    c.sendall(bytes([3, 0, 0, 19, 14, 0xD0, 0, 0, 0, 0, 0, 2, 0, 8, 0, 2, 0, 0, 0]))
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(t + "/s.crt", t + "/s.key")
    ctx.wrap_socket(c, server_side=True).close(); os._exit(0)
PY
sed "s/3389/$(cat "$t/port")/" "$t/rdp.sh" >"$t/rdp-port.sh"
out=$(settings=$t/settings.json bash -c "set -euo pipefail; setting() { echo 127.0.0.1; }; source '$t/rdp-port.sh'; rdp_check" 2>&1) || true
[[ $out == *"picked CredSSP (NLA)"* && $out == *"TLS handshake done"* ]] && echo "ok   rdp-check reads the negotiation and the TLS handshake" || { echo "FAIL: rdp-check: $out"; fails=$((fails + 1)); }
out=$(bash -c "set -euo pipefail; setting() { echo 127.0.0.1; }; source '$t/rdp-port.sh'; rdp_check" 2>&1) || true
[[ $out == *"did not answer"* ]] && echo "ok   rdp-check says so when nothing answers" || { echo "FAIL: rdp-check closed port: $out"; fails=$((fails + 1)); }

# The test passwords never outlive a test build: destroy and a plain configure delete the keys file.
n=$(grep -c 'rm -f "\$keys/desktop-test-login"' "$wrapper")
[[ $n -eq 2 ]] && echo "ok   destroy and plain configure both delete the test login file" || { echo "FAIL: the test login file is deleted in $n place(s), want 2"; fails=$((fails + 1)); }
grep -q 'status/shutdown' "$wrapper" && echo "ok   desktop stop asks the VM to shut down" || { echo "FAIL: no desktop stop"; fails=$((fails + 1)); }

# The package install is retried: the first dnf run on a fresh VM loses a cache file (2026-11-19 and 11-20).
python3 -I - "$here/hosts/ansible/roles/desktop/tasks/main.yml" <<'PY' && echo "ok   the desktop package task is retried" || { echo "FAIL: the desktop package task has no retry"; fails=$((fails + 1)); }
import sys, yaml
t = [x for x in yaml.safe_load(open(sys.argv[1])) if x.get("name") == "desktop | The desktop packages"][0]
assert t["retries"] >= 3 and "until" in t
PY

if [[ $fails -gt 0 ]]; then echo "desktop configure vars: $fails test(s) failed"; exit 1; fi
echo "desktop configure vars: all tests passed"
