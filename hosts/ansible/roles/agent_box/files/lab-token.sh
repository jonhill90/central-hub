#!/bin/bash
# /usr/local/libexec/agent-box/lab-token.sh: makes the agents' lab token (agentlab@pve!lab) on the Proxmox host and stores it on the
# box for rebuild-prod, so prod's check no longer fails on a missing /etc/agent-keys/proxmox-lab.env. It runs as `hostops`, which
# holds the host key, and hands the secret to lab-token-put.sh (as the keys user) on a pipe. Installed by the agent_box role.
#   sudo -n -u hostops /usr/local/libexec/agent-box/lab-token.sh status   whether the host has the token and the box has the file
#   sudo -n -u hostops /usr/local/libexec/agent-box/lab-token.sh mint     makes the token (privsep, expiring in 30 days) and stores it
# mint refuses when the box already has the file or the host already has the token: a renewal is a delete (`pveum user token remove`)
# and waits on its own go. If storing fails after the host made the token, mint removes that token again, so no secret is left
# that nothing holds. It prints no secret, no address and no key: only what it did.
# After a mint, run the agent-access job (proxmox-host.sh apply-recorded agent-access ...) once: a privilege-separated token has
# only its own ACLs, and agent-access.sh adds them once the token exists (runbook step 4).
set -euo pipefail
umask 077
dir=/etc/agent-keys-host
libexec=/usr/local/libexec/agent-box
inventory=$dir/inventory/hosts.yml
action=${1:-}
[[ $# -eq 1 && ( $action == status || $action == mint ) ]] || { echo "usage: lab-token status|mint" >&2; exit 2; }
[[ -f $inventory && -f $dir/id_ed25519 && -f $dir/known_hosts ]] || { echo "lab-token: no inventory or key in $dir; the controller's install has not run" >&2; exit 1; }
address=$(python3 -I -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["proxmox"]["hosts"]["proxmox_host"]["ansible_host"])' "$inventory")
[[ $address =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "lab-token: the inventory's host address is not an IPv4 address" >&2; exit 1; }
host() { ssh -n -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$dir/known_hosts" -i "$dir/id_ed25519" "root@$address" "$@"; }
put() { sudo -n -u keys "$libexec/lab-token-put.sh" "$@"; }
on_host=no
if host "pveum user token list agentlab@pve --output-format json" | grep -q '"tokenid":"lab"'; then on_host=yes; fi
on_box=$(put exists </dev/null || true)
echo "lab-token: token on the host: $on_host; file on the box: ${on_box:-absent}"
[[ $action == status ]] && exit 0
[[ $on_host == no ]] || { echo "lab-token: the host already has agentlab@pve!lab; a renewal is a delete and waits on its own go" >&2; exit 1; }
[[ $on_box != present ]] || { echo "lab-token: the box already has proxmox-lab.env; nothing was made" >&2; exit 1; }
expire=$(( $(date +%s) + 30 * 24 * 3600 ))
if host "pveum user token add agentlab@pve lab --privsep 1 --expire $expire --output-format json" | put put; then
  echo "lab-token: PASS: token made on the host (expires in 30 days) and stored on the box; run the agent-access job next"
else
  host "pveum user token remove agentlab@pve lab" >/dev/null 2>&1 || true
  echo "lab-token: FAIL: storing the token failed; the host's token was removed again" >&2
  exit 1
fi
