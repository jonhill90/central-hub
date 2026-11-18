#!/usr/bin/env bash
# The agents' Proxmox tokens must never hold the rights that change realms, groups, users or ACLs: those are the
# ones the sign-in through Keycloak (role proxmox_sso) needs, and they belong to the host job, which logs in as
# root (docs/runbooks/sign-in-to-proxmox-through-keycloak.md, "Which Proxmox rights this needs"). It reads every
# privilege list in the two bootstrap scripts that make a token's roles, and fails when one names a forbidden
# right, or when it finds no list at all (so a renamed variable can't turn this into a pass).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root=$(cd "$here/../.." && pwd)
forbidden='Realm\.Allocate|Realm\.AllocateUser|Group\.Allocate|Permissions\.Modify|User\.Modify|Sys\.Modify'
fail=0
lists=0
for f in agent-access.sh iac-access.sh; do
  file=$root/hosts/terraform/home/bootstrap/$f
  # Every NAME_PRIVS="..." or PRIVS="..." assignment, and every literal list in a role loop.
  while IFS= read -r line; do
    lists=$((lists + 1))
    if printf '%s' "$line" | grep -Eq "$forbidden"; then
      echo "not ok  $f holds a forbidden right in: ${line:0:60}..."
      fail=1
    fi
  done < <(grep -E '^[A-Z_]*PRIVS="' "$file"; grep -E '^for r in ".*:' "$file")
done
if [ "$lists" -lt 6 ]; then
  echo "not ok  found $lists privilege lists, expected at least 6: a variable was renamed"
  exit 1
fi
[ "$fail" -eq 0 ] || exit 1
echo "ok   $lists privilege lists in agent-access.sh and iac-access.sh hold none of: ${forbidden//\\/}"

# The host job reaches the host as root, which is why it needs no token right.
if ! grep -q '^      ansible_user: root$' "$root/hosts/ansible/roles/agent_box/templates/proxmox-host-inventory.yml.j2"; then
  echo "not ok  the host job's inventory no longer logs in as root, so the runbook's rights section is wrong"
  exit 1
fi
echo "ok   the host job's inventory logs in as root"
