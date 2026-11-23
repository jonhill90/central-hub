#!/usr/bin/env bash
# The three wrappers that build the box's copy of prod's inventory, rebuild-prod.sh (the rebuild), c1-ansible.sh (`gitops`) and
# openbao-prod.sh (`gitops`), pass the same variables to prod's root Application, because all exec files/prod-root-vars.py. Found 2026-11-22: `c1-ansible check gitops`
# planned to remove openbaoAdminAddress, notebookRunner and localPathStableFolders, which prod's rebuild passes, so applying it would
# have dropped what they switch on. This runs each wrapper's own inventory-builder Python (cut from the script) on one source inventory
# and one settings file, and checks:
#   1. every k8s_gitops_source_* variable on k8s_nodes is the same in the copies, and there are at least seven; openbao-prod's has these
#      and, on top, appSecretsStore and the store's route (the apps' move to the store, its own gated step), and no more;
#   2. values the controller's inventory holds for them are replaced in all, not passed through;
#   3. a seal node the inventory does not have stops all;
#   4. openbao-prod without the rebuild's stable-folders marker leaves localPathStableFolders out, and nothing else changes.
# Usage: .github/hosts-check/tests/test_prod_root_vars.sh   (needs python3 with PyYAML)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
files=hosts/ansible/roles/agent_box/files
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
cut_py() { awk "/<<'PY'/ { n++; if (n == 1) { on = 1; next } } on && /^PY\$/ { exit } on { print }" "$1"; }
cut_py $files/rebuild-prod.sh > "$t/rebuild.py"; cut_py $files/c1-ansible.sh > "$t/c1.py"; cut_py $files/openbao-prod.sh > "$t/bao.py"
[ -s "$t/rebuild.py" ] && [ -s "$t/c1.py" ] && [ -s "$t/bao.py" ] || { echo "FAIL: an inventory builder was not found in a wrapper"; exit 1; }
mkdir -p "$t/keys/prod" "$t/repo"
src() { cat <<S
all:
  children:
    proxmox:
      hosts:
        pve-a: {ansible_host: 192.0.2.1}
    k8s_nodes:
      vars:
        ansible_ssh_private_key_file: /Users/someone/.ssh/id
        k8s_gitops_cluster_labels: {env: prod}
        k8s_gitops_source_notebook_runner: false
        k8s_gitops_source_openbao_admin_address: 10.9.9.9
        k8s_gitops_source_openbao_measure: true
      children:
        k8s_control_plane:
          hosts:
            cp-a: {ansible_host: 192.0.2.10}
        k8s_workers:
          hosts:
            wk-a: {ansible_host: 192.0.2.11}
S
}
src > "$t/src.yml"
echo '{"seal_node": "wk-a", "store_host": "bao.invalid", "box_cidr": "192.0.2.50/32", "admin_address": "192.0.2.60"}' > "$t/settings.json"
build() { # <seal node> -> both copies in $t/rebuild.yml and $t/c1.yml; prints each builder's exit code
  jq -n --arg s "$1" '{seal_node: $s, store_host: "bao.invalid", box_cidr: "192.0.2.50/32", admin_address: "192.0.2.60"}' > "$t/settings.json" 2>/dev/null ||
    echo "{\"seal_node\": \"$1\", \"store_host\": \"bao.invalid\", \"box_cidr\": \"192.0.2.50/32\", \"admin_address\": \"192.0.2.60\"}" > "$t/settings.json"
  rm -f "$t/rebuild.yml" "$t/c1.yml"
  python3 -I -c "$(cat "$t/rebuild.py")" "$t/src.yml" "$t/rebuild.yml" "$t/key" "$t/known" "$t/keys/prod" "$t/keys" "$t/certs" "$t/settings.json" "$t/repo" "$t/sftp" \
    "$PWD/$files/prod-root-vars.py" > "$t/rebuild.out" 2>&1; r1=$?
  python3 -I -c "$(cat "$t/c1.py")" "$t/src.yml" "$t/c1.yml" "$t/key" "$t/known" "$t/keys/prod/identity-theme" "$t/sftp" gitops "$t/settings.json" \
    "$PWD/$files/prod-root-vars.py" > "$t/c1.out" 2>&1; r2=$?
  rm -f "$t/bao.yml"; touch "$t/stable"
  python3 -I -c "$(cat "$t/bao.py")" "$t/src.yml" "$t/bao.yml" "$t/key" "$t/known" "$t/settings.json" "${STABLE:-$t/stable}" \
    "$PWD/$files/prod-root-vars.py" > "$t/bao.out" 2>&1; r3=$?
}
rootvars() { python3 -I -c 'import sys, yaml
d = yaml.safe_load(open(sys.argv[1])); v = d["all"]["children"]["k8s_nodes"]["vars"]
for k in sorted(v):
    if k.startswith("k8s_gitops_source_"): print(k, "=", v[k])' "$1"; }
build wk-a
a=$(rootvars "$t/rebuild.yml"); b=$(rootvars "$t/c1.yml"); c=$(rootvars "$t/bao.yml")
extra=$'k8s_gitops_source_app_secrets_store = openbao\nk8s_gitops_source_openbao_route = True'
if [[ $r1 -eq 0 && $r2 -eq 0 && $r3 -eq 0 && -n $a && $a == "$b" && $(wc -l <<< "$a") -ge 7 && $(sort <<< "$a"$'\n'"$extra") == "$(sort <<< "$c")" ]]; then
  ok "1. the rebuild's and c1-ansible's copies carry the same $(wc -l <<< "$a") k8s_gitops_source_* variables; openbao-prod's has those and the apps' store and route"
else bad "1. rc $r1/$r2/$r3 | rebuild: $a | c1: $b | bao: $c | $(cat "$t/rebuild.out" "$t/c1.out" "$t/bao.out")"; fi
if [[ $a == *"notebook_runner = True"* && $a == *"admin_address = 192.0.2.60"* && $a == *"local_path_stable_folders = True"* && $a != *"10.9.9.9"* && $a != *"measure"* && $b != *"10.9.9.9"* && $c != *"10.9.9.9"* && $c != *"measure"* ]]; then
  ok "2. the inventory's own values for them are replaced, not passed through, in all three"
else bad "2. $a | $c"; fi
build no-such-node
if [[ $r1 -ne 0 && $r2 -ne 0 && $r3 -ne 0 && $(cat "$t/rebuild.out") == *"seal_node is not a k8s_nodes host"* && $(cat "$t/c1.out") == *"seal_node is not a k8s_nodes host"* &&
      $(cat "$t/bao.out") == *"seal_node is not a k8s_nodes host"* ]]; then
  ok "3. a seal node the inventory lacks stops all three"
else bad "3. $r1/$r2/$r3 $(cat "$t/rebuild.out" "$t/c1.out" "$t/bao.out")"; fi
STABLE=$t/no-such-marker build wk-a
c2=$(rootvars "$t/bao.yml")
if [[ $r3 -eq 0 && $c2 != *"local_path_stable_folders"* && $(grep -vc local_path_stable_folders <<< "$c") -eq $(wc -l <<< "$c2") ]]; then
  ok "4. openbao-prod with no stable-folders marker leaves only that variable out"
else bad "4. $c2"; fi
exit $fail
