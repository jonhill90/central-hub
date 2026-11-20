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
assert e["desktop_test_login"] is True and e["desktop_lock_admin"] is False and e["desktop_rdp_extra_sources"] == ["127.0.0.1/32"]
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

# On a test build rdp-check then does a real login with xfreerdp +auth-only. A stub xfreerdp stands in: it reads the
# arguments from stdin (/args-from:stdin), records its own command line, and exits 0 only for the right password.
# The password must reach it on stdin only, and must never be printed.
mkdir -p "$t/lk" "$t/bin" "$t/state"
echo '{"login_password": "LOGINPW", "rdp_password": "RDPPW-test"}' >"$t/lk/desktop-test-login"
cat >"$t/bin/xfreerdp3" <<'STUB'
#!/bin/bash
echo "$*" >"$STUBDIR/argv"
cat >"$STUBDIR/stdin"
grep -qx '/p:RDPPW-test' "$STUBDIR/stdin" && exit 0 || exit 131
STUB
chmod +x "$t/bin/xfreerdp3"
start_stub() {
python3 -I - "$t" <<'PY'
import os, socket, ssl, sys
t = sys.argv[1]
srv = socket.socket(); srv.bind(("127.0.0.1", 0)); srv.listen(1)
open(t + "/port", "w").write(str(srv.getsockname()[1]))
if os.fork() == 0:
    c, _ = srv.accept(); c.recv(512)
    c.sendall(bytes([3, 0, 0, 19, 14, 0xD0, 0, 0, 0, 0, 0, 2, 0, 8, 0, 2, 0, 0, 0]))
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(t + "/s.crt", t + "/s.key")
    ctx.wrap_socket(c, server_side=True).close(); os._exit(0)
PY
sed "s/3389/$(cat "$t/port")/" "$t/rdp.sh" >"$t/rdp-port.sh"
}
run_login() { PATH="$t/bin:$PATH" STUBDIR=$t work=$t/state keys=$t/lk bash -c "set -euo pipefail; setting() { echo 127.0.0.1; }; source '$t/rdp-port.sh'; rdp_check" 2>&1; }
start_stub; out=$(run_login) || true
[[ $out == *"login PASS"* && $out != *RDPPW* ]] && echo "ok   a test build's rdp-check prints login PASS and no password" || { echo "FAIL: rdp-check login pass: $out"; fails=$((fails + 1)); }
grep -q 'args-from:stdin' "$t/argv" && ! grep -q RDPPW "$t/argv" && grep -q '^+auth-only$' "$t/stdin" && grep -q '^/u:owner$' "$t/stdin" && echo "ok   the password goes on stdin, not the command line" || { echo "FAIL: argv/stdin: $(cat "$t/argv")"; fails=$((fails + 1)); }
echo '{"login_password": "LOGINPW", "rdp_password": "WRONG"}' >"$t/lk/desktop-test-login"
start_stub; out=$(run_login) || true
[[ $out == *"login FAIL (xfreerdp exit 131)"* && $out != *WRONG* ]] && echo "ok   a refused login prints login FAIL and no password" || { echo "FAIL: rdp-check login fail: $out"; fails=$((fails + 1)); }
rm -f "$t/bin/xfreerdp3"; start_stub; out=$(PATH=/usr/bin:/bin STUBDIR=$t work=$t/state keys=$t/lk bash -c "set -euo pipefail; setting() { echo 127.0.0.1; }; source '$t/rdp-port.sh'; rdp_check" 2>&1) || true
if command -v xfreerdp3 xfreerdp >/dev/null 2>&1; then echo "skip rdp-check without a client (this machine has one)"; else
[[ $out == *"no xfreerdp"* ]] && echo "ok   a test build without xfreerdp says so" || { echo "FAIL: no-client message: $out"; fails=$((fails + 1)); }; fi

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

# gdm is started on every build, queued behind the console password prompt (tty1), without blocking the run (2026-11-20).
python3 -I - "$here/hosts/ansible/roles/desktop/tasks/main.yml" <<'PY' && echo "ok   gdm starts after the console prompt, without blocking" || { echo "FAIL: gdm start or its ordering is missing"; fails=$((fails + 1)); }
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1]))
byname = {x["name"]: x for x in tasks}
t = byname["desktop | gdm is started"]
assert t["ansible.builtin.systemd_service"] == {"name": "gdm.service", "state": "started", "daemon_reload": True, "no_block": True} and "when" not in t
d = byname["desktop | gdm starts after the console password prompt"]["ansible.builtin.copy"]
assert "After=desktop-set-password.service" in d["content"] and d["dest"].startswith("/etc/systemd/system/gdm.service.d/")
names = [x["name"] for x in tasks]
assert names.index("desktop | The console prompt starts now") < names.index("desktop | gdm is started")
PY

# The prompt's ExecStartPost starts gdm, not getty@tty1 (gdm conflicts with it, so a getty start would cancel gdm's queued
# start), and a test build feeds throwaway passwords to the real prompt unit on stdin (2026-11-20, reviewer on #795).
tpl=$here/hosts/ansible/roles/desktop/templates/desktop-set-password.service.j2
if grep -q '^ExecStartPost=/usr/bin/systemctl --no-block start gdm.service$' "$tpl" && ! grep -q '^ExecStartPost=.*getty' "$tpl"; then
  echo "ok   the prompt's ExecStartPost starts gdm, not the getty"
else echo "FAIL: the prompt's ExecStartPost"; fails=$((fails + 1)); fi
python3 -I - "$here/hosts/ansible/roles/desktop/tasks/main.yml" <<'PY' && echo "ok   a test build runs the real prompt on throwaway passwords" || { echo "FAIL: the test build's prompt feed"; fails=$((fails + 1)); }
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1]))
by = {x["name"]: x for x in tasks}
f = by["desktop | Test build, the throwaway passwords are fed to the console prompt"]["ansible.builtin.copy"]
assert f["dest"] == "/run/desktop-test-passwords" and f["mode"] == "0600" and f["content"].count("\n") == 4
assert "desktop_marker.stat.exists" in by["desktop | Test build, the throwaway passwords are fed to the console prompt"]["when"]
assert by["desktop | Test build, the throwaway passwords are fed to the console prompt"]["no_log"] is True
d = by["desktop | Test build, the console prompt reads them"]["ansible.builtin.copy"]
assert "StandardInput=file:/run/desktop-test-passwords" in d["content"] and "ExecStartPost=/usr/bin/rm -f /run/desktop-test-passwords" in d["content"]
assert "ExecStopPost=/usr/bin/rm -f /run/desktop-test-passwords" in d["content"]
r = by["desktop | Not a test build, the test drop-in and the feed file are removed"]
assert r["ansible.builtin.file"]["state"] == "absent" and "10-test-passwords.conf" in " ".join(r["loop"]) and "desktop_test_login" in r["when"]
assert by["desktop | The feed file is absent when the prompt will not run"]["ansible.builtin.file"]["state"] == "absent"
names = [x["name"] for x in tasks]
assert names.index("desktop | Not a test build, the test drop-in and the feed file are removed") < names.index("desktop | The units are enabled") < names.index("desktop | The console prompt starts now")
# no task sets the passwords or the marker for the test build behind the prompt's back
assert names.index("desktop | The password marker is looked up") < names.index("desktop | Test build, the throwaway passwords are fed to the console prompt")
assert not [n for n in names if n in ("desktop | Test build, the password marker is written", "desktop | Test build, the login password is set from the box")]
PY

if [[ $fails -gt 0 ]]; then echo "desktop configure vars: $fails test(s) failed"; exit 1; fi
echo "desktop configure vars: all tests passed"
