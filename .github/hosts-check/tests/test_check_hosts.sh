#!/usr/bin/env bash
# Test cases for check_hosts.py: each breaks a copy of hosts/ one way and expects the check to
# fail; the unbroken copy must pass. Run from anywhere; run.sh terraform runs it.
set -euo pipefail
cd "$(dirname "$0")/../../.."
check=$PWD/.github/hosts-check/check_hosts.py
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failed=0

fresh() {
  rm -rf "$work/repo"
  mkdir -p "$work/repo"
  cp -r hosts "$work/repo/"
  git -C "$work/repo" init -q
  git -C "$work/repo" add -A
}

expect() { # expect pass|fail <name>
  local want=$1 name=$2 got=pass
  git -C "$work/repo" add -A
  python3 "$check" "$work/repo" >"$work/out" 2>&1 || got=fail
  if [ "$got" = "$want" ]; then
    echo "ok: $name"
  else
    echo "NOT OK: $name: expected $want, got $got"
    cat "$work/out"
    failed=1
  fi
}

fresh
expect pass "hosts/ as it is"

fresh
rm "$work/repo/hosts/terraform/home/network/backend.tf"
expect fail "a run folder without backend.tf (Terraform rule 1)"

fresh
printf 'locals {\n  x = 1\n}\n' >> "$work/repo/hosts/terraform/home/network/main.tf"
expect fail "a locals block (Terraform rule 2)"

fresh
echo 'proxmox_node_name = "x"' > "$work/repo/hosts/terraform/home/network/home.tfvars"
git -C "$work/repo" add -f hosts/terraform/home/network/home.tfvars
expect fail "a tracked home.tfvars (Terraform rule 5)"

fresh
rm "$work/repo/hosts/ansible/roles/k8s_node/meta/argument_specs.yml"
expect fail "a role without meta/argument_specs.yml (Ansible rule 1)"

fresh
printf -- '---\ngalaxy_info: {}\n' > "$work/repo/hosts/ansible/roles/k8s_node/meta/main.yml"
expect fail "a role with meta/main.yml (Ansible rule 2)"

fresh
cp "$work/repo/hosts/ansible/inventories/home/hosts.example.yml" "$work/repo/hosts/ansible/inventories/home/hosts.yml"
git -C "$work/repo" add -f hosts/ansible/inventories/home/hosts.yml
expect fail "a tracked filled inventory (Ansible rule 4)"

exit $failed
