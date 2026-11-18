#!/bin/bash
# Tests for the values `desktop configure` passes to playbooks/desktop.yml (hosts/ansible/roles/agent_box/files/desktop.sh)
# and the trust check's default names (role desktop, defaults/main.yml):
#   1. the zone is read from the prod inventory's k8s_gateway_zone, wherever it sits, and passed as
#      desktop_trust_check_zone; no zone, two different zones or a templated value stops the run;
#   2. with a zone, the role's default names are <app>.<zone> for the gateway name check's apps; without one, none.
# The wrapper's Python is cut from desktop.sh itself, so the test runs the shipped text.
set -euo pipefail
here=$(cd "$(dirname "$0")/../../.." && pwd)
wrapper=$here/hosts/ansible/roles/agent_box/files/desktop.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

awk '/"\$prodinv" <<'"'"'PY'"'"'$/ {on=1; next} on && /^PY$/ {exit} on {print}' "$wrapper" >"$t/vars.py"
[[ -s $t/vars.py ]] || { echo "FAIL: the configure Python was not found in desktop.sh"; exit 1; }
echo '{"address": "192.0.2.91", "rdp_source": "192.0.2.5/32"}' >"$t/settings.json"
echo "chain" >"$t/chain.crt"

fails=0
run() { python3 -I "$t/vars.py" "$t/settings.json" "$t/inv.json" "$t/extra.json" "$t/chain.crt" "$t/prod.yml"; }
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
got=$(names -e desktop_trust_check_zone=lab.example.com)
[[ $got == "$want" ]] && echo "ok   with a zone, the names are each app's short name" || { echo "FAIL: names with a zone: $got"; fails=$((fails + 1)); }
got=$(names)
[[ $got == "[]" ]] && echo "ok   without a zone, no names" || { echo "FAIL: names without a zone: $got"; fails=$((fails + 1)); }
gw=$(python3 -I -c 'import sys,yaml; print(" ".join(yaml.safe_load(open(sys.argv[1]))["nameCheck"]["apps"]))' "$here/hosts/kubernetes/home/c1/apps/gateway/values.yaml")
role=$(python3 -I -c 'import sys,yaml; print(" ".join(yaml.safe_load(open(sys.argv[1]))["desktop_trust_check_apps"]))' "$here/hosts/ansible/roles/desktop/defaults/main.yml")
[[ $gw == "$role" ]] && echo "ok   the apps are the gateway name check's apps" || { echo "FAIL: apps differ: gateway '$gw', desktop '$role'"; fails=$((fails + 1)); }

if [[ $fails -gt 0 ]]; then echo "desktop configure vars: $fails test(s) failed"; exit 1; fi
echo "desktop configure vars: all tests passed"
