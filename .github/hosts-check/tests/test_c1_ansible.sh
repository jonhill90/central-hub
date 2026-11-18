#!/usr/bin/env bash
# The c1-ansible wrapper (hosts/ansible/roles/agent_box/files/c1-ansible.sh), with stand-ins for git, ansible-inventory and
# ansible-playbook:
#   1. Usage: no action, an unknown name, apply with no clearance id or a malformed one, extra arguments: exit 2, nothing run.
#   2. list names the identity playbook; a name with a private values file stops while the file is missing.
#   3. check runs the playbook with --check --diff on the box's copy of the inventory: the Mac's ssh settings and proxmox group
#      are gone, the box's key and plain ssh are set, and the values file is named to the play.
#   4. apply runs the playbook without --check, never with realm replace, and logs the clearance id; a host labelled env dev
#      refuses before any run.
#   5. log prints the run's own lines.
# Usage: .github/hosts-check/tests/test_c1_ansible.sh   (needs python3 with PyYAML, flock)
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

venv=$t/libexec/ansible-venv/bin
mkdir -p "$t/bin" "$venv" "$t/keys/prod" "$t/work/state" "$t/work/central-hub" "$t/run"
ln -s "$(command -v python3)" "$venv/python3"
cat > "$t/bin/git" <<'S'
#!/bin/bash
case "$*" in
  *"remote get-url"*) echo https://example.invalid/central-hub.git ;;
  clone*) mkdir -p "${@: -1}/.git" "${@: -1}/hosts/ansible/playbooks"; : > "${@: -1}/hosts/ansible/playbooks/k8s-identity.yml" ;;
  *rev-parse*) echo abc1234 ;;
esac
exit 0
S
# shellcheck disable=SC2016
sed -n '/^cat > "\$venv\/ansible-inventory"/,/^EOF/p' .github/hosts-check/tests/test_openbao_prod.sh | sed "s/^EOF\$/EOF/" > "$t/inv-stub.sh"
bash -c "venv=$venv; $(cat "$t/inv-stub.sh")"
cat > "$venv/ansible-playbook" <<S
#!/bin/bash
echo "playbook \$*" >> $t/calls
cp "\${2%/}/hosts.yml" $t/seen-inventory.yml
echo "PLAY RECAP"
S
chmod +x "$t/bin/git" "$venv/ansible-inventory" "$venv/ansible-playbook"
sed -e "s|^keys=.*|keys=$t/keys|" -e "s|^libexec=.*|libexec=$t/libexec|" -e "s|^work=.*|work=$t/work|" \
    -e "s|PATH=\$libexec/ansible-venv/bin:/usr/local/bin|PATH=\$libexec/ansible-venv/bin:$t/bin:/usr/local/bin|" \
    -e "s|^declare -A needs_file=.*|declare -A needs_file=([identity]=\"$t/keys/prod/identity.env\")|" \
    hosts/ansible/roles/agent_box/files/c1-ansible.sh > "$t/run/c1-ansible.sh"
if ! grep -q "^keys=$t/keys" "$t/run/c1-ansible.sh" || ! grep -q "identity.env" "$t/run/c1-ansible.sh"; then
  echo "FAIL the test could not point the wrapper at its folders"; exit 1
fi
run() { : > "$t/calls"; bash "$t/run/c1-ansible.sh" "$@" > "$t/out" 2>&1; rc=$?; out=$(cat "$t/out"); calls=$(cat "$t/calls"); }
inventory() { printf '%s\n' "$@" > "$t/keys/prod/inventory-hosts.yml"; }
prod_inv=("all:" "  children:" "    proxmox:" "      hosts:" "        pve-a: {ansible_host: 192.0.2.1}"
          "    k8s_nodes:" "      vars:" "        ansible_ssh_common_args: -o ProxyJump=root@192.0.2.1"
          "        ansible_ssh_private_key_file: /Users/someone/.ssh/id"
          "      children:" "        k8s_control_plane:" "          hosts:" "            cp-a: {ansible_host: 192.0.2.10}")
inventory "${prod_inv[@]}"
echo node-key > "$t/keys/prod-node-key"
clr=cmsg_01X43rfNYp4H1dL1V2dkfkwNaaaaaaaaaaaaaaaaaaaaaa

r1=""
for args in "" "frob" "check" "check nope" "apply identity" "apply identity notanid" "list extra" "check identity extra"; do
  # shellcheck disable=SC2086
  run $args; r1+="$rc:${calls:-none} "
done
if [[ $r1 == "2:none 2:none 2:none 2:none 2:none 2:none 2:none 2:none " ]]; then ok "1. usage errors and unknown names, nothing run"; else bad "1. $r1"; fi

run list; l=$out
run check identity
if [[ $l == identity && $rc -ne 0 && $out == *"identity.env is missing"* && -z $calls ]]; then ok "2. list; a missing values file stops the run"; else bad "2. $l $rc $out"; fi

echo "X=1" > "$t/keys/prod/identity.env"
ens='{"k8s_identity_ensure_clients":["proxmox"]}'
run check identity
seen=$(cat "$t/seen-inventory.yml" 2>/dev/null)
if [[ $rc -eq 0 && $calls == *"playbooks/k8s-identity.yml -e k8s_identity_values_file=$t/keys/prod/identity.env -e k8s_identity_realm_replace=false --tags all,clients -e $ens --check --diff" &&
      $seen != *ProxyJump* && $seen != */Users/* && $seen != *pve-a* && $seen == *"$t/keys/prod-node-key"* ]]; then
  ok "3. check: --check --diff on the box's copy of the inventory"
else bad "3. $rc [$calls] $out"; fi

run apply identity "$clr"
if [[ $rc -eq 0 && $calls != *--check* && $calls == *"playbooks/k8s-identity.yml -e k8s_identity_values_file="* && $calls == *"-e k8s_identity_realm_replace=false"* && $calls == *"--tags all,clients"* && $calls == *"$ens"* && $out == *"clearance $clr"* ]]; then
  ok "4a. apply: no --check, the clearance id logged"
else bad "4a. $rc [$calls] $out"; fi
inventory "${prod_inv[@]}" "            cp-b: {ansible_host: 192.0.2.11, k8s_gitops_cluster_labels: {env: dev}}"
run apply identity "$clr"
if [[ $rc -ne 0 && -z $calls && $out == *"not prod"* ]]; then ok "4b. a host labelled env dev refuses before any run"; else bad "4b. $rc [$calls] $out"; fi

inventory "${prod_inv[@]}"
run check identity; run log
if [[ $rc -eq 0 && $out == *"c1-ansible: check identity at central-hub abc1234"* && $out == *"PLAY RECAP"* ]]; then ok "5. log prints the run's own lines"; else bad "5. $rc $out"; fi
exit "$fail"
